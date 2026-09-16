#!/usr/bin/env python3
"""Assess GCP lab ingress policy, including priorities and implicit deny."""

import argparse
import ipaddress
import json
import subprocess
import sys


class PolicyError(ValueError):
    pass


UNIVERSE = [(0, 2**32 - 1)]


def merge(ranges):
    result = []
    for low, high in sorted(ranges):
        if result and low <= result[-1][1] + 1:
            result[-1] = (result[-1][0], max(high, result[-1][1]))
        else:
            result.append((low, high))
    return result


def subtract(ranges, removed):
    result = []
    for low, high in ranges:
        cursor = low
        for start, end in removed:
            if end < cursor:
                continue
            if start > high:
                break
            if start > cursor:
                result.append((cursor, start - 1))
            cursor = max(cursor, end + 1)
        if cursor <= high:
            result.append((cursor, high))
    return result


def addresses(values):
    result = []
    for value in values:
        network = ipaddress.ip_network(value, strict=False)
        if network.version == 4:
            result.append((int(network.network_address), int(network.broadcast_address)))
    return merge(result)


def contains(ranges, address):
    return any(low <= address <= high for low, high in ranges)


def gcloud_json(args, *arguments):
    try:
        result = subprocess.run(
            ["gcloud", *arguments, "--project", args.project, "--format=json"],
            check=True, capture_output=True, text=True, timeout=90,
        )
    except subprocess.CalledProcessError as error:
        raise PolicyError(f"GCP query failed: {error.stderr.strip()}") from error
    except subprocess.TimeoutExpired as error:
        raise PolicyError("GCP query timed out") from error
    return json.loads(result.stdout)


def source_addresses(rule, instances, network):
    sources = addresses(rule.get("sourceRanges", []))
    tags = set(rule.get("sourceTags", []))
    accounts = set(rule.get("sourceServiceAccounts", []))
    for vm in instances:
        matches = tags.intersection(vm.get("tags", {}).get("items", [])) or accounts.intersection(
            account["email"] for account in vm.get("serviceAccounts", [])
        )
        if matches:
            for nic in vm["networkInterfaces"]:
                if nic["network"] == network:
                    sources.extend(addresses([nic["networkIP"]]))
    # GCP combines source ranges and source identities with OR, not AND.
    if not any(rule.get(key) for key in ("sourceRanges", "sourceTags", "sourceServiceAccounts")):
        return UNIVERSE
    return merge(sources)


def matches_protocol(entries, protocol, port):
    for entry in entries:
        value = str(entry["IPProtocol"]).lower()
        if value not in (protocol, {"tcp": "6", "icmp": "1"}[protocol], "all"):
            continue
        if value == "all" or protocol == "icmp" or not entry.get("ports"):
            return True
        for item in entry["ports"]:
            bounds = item.split("-")
            low, high = int(bounds[0]), int(bounds[-1])
            if len(bounds) > 2 or not 0 <= low <= high <= 65535:
                raise PolicyError(f"Invalid firewall port range: {item}")
            if low <= port <= high:
                return True
    return False


def allowed_sources(effective, instances, network, destination, protocol, port):
    # Do not silently ignore organization/global/regional firewall policy layers.
    if effective.get("firewallPolicys") or effective.get("firewallPolicies"):
        raise PolicyError("Hierarchical/network firewall policies are outside this lab validator's scope")
    if set(effective) - {"firewalls", "firewallPolicys", "firewallPolicies"}:
        raise PolicyError("Unsupported effective-firewall response")
    raw_rules = effective.get("firewalls", [])
    if not isinstance(raw_rules, list):
        raise PolicyError("Invalid effective-firewall rules")
    rules = []
    for rule in raw_rules:
        if rule.get("disabled", False):
            continue
        direction = rule.get("direction", "INGRESS")
        if direction == "EGRESS":
            continue
        if direction != "INGRESS" or rule["network"] != network:
            raise PolicyError("Unexpected firewall direction or network")
        if rule.get("destinationRanges") and not contains(addresses(rule["destinationRanges"]), destination):
            continue
        action = "deny" if rule.get("denied") else "allow"
        entries = rule.get("denied") or rule.get("allowed")
        if not entries or (rule.get("denied") and rule.get("allowed")):
            raise PolicyError("Invalid firewall action")
        priority = rule.get("priority", 1000)
        if type(priority) is not int or not 0 <= priority <= 65535:
            raise PolicyError("Invalid firewall priority")
        if matches_protocol(entries, protocol, port):
            rules.append((priority, action, source_addresses(rule, instances, network)))
    # Equal-priority deny wins. Unmatched ingress is implicitly denied.
    rules.sort(key=lambda rule: (rule[0], rule[1] != "deny"))
    remaining = UNIVERSE
    allowed = []
    for _, action, sources in rules:
        matched = subtract(remaining, subtract(UNIVERSE, sources))
        if action == "allow":
            allowed.extend(matched)
        remaining = subtract(remaining, sources)
    return merge(allowed)


def assess(args):
    trusted = ipaddress.IPv4Address(args.trusted_ip)
    if not trusted.is_global:
        raise PolicyError("Bastion SSH must originate from the validation client's public IPv4 address")
    instances = gcloud_json(args, "compute", "instances", "list")
    hosts = {}
    for role in ("bastion", "web", "api", "database"):
        name = f"vm-{role}-{args.deployment_id}"
        candidates = [vm for vm in instances if vm["name"] == name and vm["zone"].endswith("/" + args.zone)]
        if len(candidates) != 1:
            raise PolicyError(f"Cannot identify the {role} VM")
        vm = candidates[0]
        nics = vm["networkInterfaces"]
        if len(nics) != 1 or nics[0].get("aliasIpRanges") or nics[0].get("ipv6Address") or nics[0].get("ipv6AccessConfigs"):
            raise PolicyError("Only the lab single-NIC, primary-IPv4 topology is supported")
        nic = nics[0]
        subnet = gcloud_json(args, "compute", "networks", "subnets", "describe", nic["subnetwork"])
        effective = gcloud_json(args, "compute", "instances", "network-interfaces",
                                "get-effective-firewalls", name, "--zone", args.zone,
                                "--network-interface", nic["name"])
        hosts[role] = {
            "ip": int(ipaddress.IPv4Address(nic["networkIP"])),
            "subnet": addresses([subnet["ipCidrRange"]]),
            "network": nic["network"],
            "effective": effective,
        }
    bastion, api = hosts["bastion"], hosts["api"]
    if len({host["network"] for host in hosts.values()}) != 1:
        raise PolicyError("Lab VMs must share one VPC")
    checks = [
        ("bastion", "tcp", 22, [(int(trusted), int(trusted))], int(trusted), "Bastion SSH"),
        *[(role, "tcp", 22, bastion["subnet"], bastion["ip"], f"{role} SSH")
          for role in ("web", "api", "database")],
        ("database", "tcp", 5432, api["subnet"], api["ip"], "Database TCP 5432"),
        *[(role, "icmp", None, bastion["subnet"], bastion["ip"], f"{role} ICMP")
          for role in ("web", "api", "database")],
    ]
    failures = []
    for role, protocol, port, approved, required, label in checks:
        host = hosts[role]
        allowed = allowed_sources(host["effective"], instances, host["network"], host["ip"], protocol, port)
        leaked = subtract(allowed, approved)
        if leaked:
            failures.append(f"{label} permits unauthorized source {ipaddress.IPv4Address(leaked[0][0])}.")
        if not contains(allowed, required):
            failures.append(f"{label} blocks its required source.")
    if failures:
        print("Bastion SSH must be restricted to the current client's public IPv4 /32. " + " ".join(failures))
        return 1
    print("Effective ingress source restrictions passed; bastion SSH is limited to the current client's public IPv4 /32.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True)
    parser.add_argument("--zone", required=True)
    parser.add_argument("--deployment-id", required=True)
    parser.add_argument("--trusted-ip", required=True)
    try:
        return assess(parser.parse_args())
    except (PolicyError, OSError, KeyError, TypeError, AttributeError, ValueError) as error:
        print(f"Cannot assess effective GCP firewall policy: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
