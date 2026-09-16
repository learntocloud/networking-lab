#!/usr/bin/env python3
"""Check inbound source restrictions on the lab's effective IPv4 NSGs."""

import argparse
import ipaddress
import json
import subprocess
import sys
from dataclasses import dataclass


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


def intersect(left, right):
    result = []
    i = j = 0
    while i < len(left) and j < len(right):
        low = max(left[i][0], right[j][0])
        high = min(left[i][1], right[j][1])
        if low <= high:
            result.append((low, high))
        if left[i][1] < right[j][1]:
            i += 1
        else:
            j += 1
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
            if cursor > high:
                break
        if cursor <= high:
            result.append((cursor, high))
    return result


def contains(ranges, value):
    return any(low <= value <= high for low, high in ranges)


def values(record, singular, plural):
    value = record.get(plural) or record.get(singular)
    if isinstance(value, str):
        value = [value]
    if not isinstance(value, list) or not value or not all(isinstance(item, str) for item in value):
        raise PolicyError(f"Missing or invalid {singular}/{plural}")
    return value


def addresses(items, tags):
    result = []
    for item in items:
        expanded = tags.get(item, [item])
        if not isinstance(expanded, list) or not expanded or not all(isinstance(value, str) for value in expanded):
            raise PolicyError(f"Invalid expansion for service tag {item}")
        for value in expanded:
            try:
                network = ipaddress.ip_network("0.0.0.0/0" if value == "*" else value, strict=False)
            except ValueError as error:
                raise PolicyError(f"Unexpanded or unsupported address prefix: {value}") from error
            if network.version == 4:
                result.append((int(network.network_address), int(network.broadcast_address)))
    return merge(result)


def rule_addresses(rule, side, tags):
    expanded = rule.get(f"expanded{side.title()}AddressPrefix")
    if expanded:
        if not isinstance(expanded, list) or not all(isinstance(value, str) for value in expanded):
            raise PolicyError(f"Invalid expanded {side} addresses")
        return addresses(expanded, {})
    return addresses(values(rule, f"{side}AddressPrefix", f"{side}AddressPrefixes"), tags)


def ports(rule, side):
    result = []
    for value in values(rule, f"{side}PortRange", f"{side}PortRanges"):
        for item in value.split(","):
            try:
                if item == "*":
                    low, high = 0, 65535
                elif "-" in item:
                    low, high = map(int, item.split("-"))
                else:
                    low = high = int(item)
            except ValueError as error:
                raise PolicyError(f"Invalid port range: {item}") from error
            if not 0 <= low <= high <= 65535:
                raise PolicyError(f"Invalid port range: {item}")
            result.append((low, high))
    return merge(result)


@dataclass
class Rule:
    priority: int
    access: str
    sources: list
    source_ports: list
    destination_ports: list


def compile_rules(group, destination, protocol):
    association = group["association"]
    if (not association or set(association) - {"networkInterface", "subnet"} or
            "/networksecuritygroups/" not in group["networkSecurityGroup"]["id"].lower()):
        raise PolicyError("Unsupported effective-policy association; security admin rules are outside this lab's scope")
    raw_rules = group.get("effectiveSecurityRules")
    tags = group.get("tagMap") or {}
    if not isinstance(raw_rules, list) or not raw_rules or not isinstance(tags, dict):
        raise PolicyError("Incomplete effective NSG rules or service-tag map")
    priorities = [rule["priority"] for rule in raw_rules if rule["direction"] == "Inbound"]
    if not {65000, 65001, 65500}.issubset(priorities):
        raise PolicyError("Effective NSG response is missing default inbound rules")
    if len(priorities) != len(set(priorities)):
        raise PolicyError("Effective NSG response has duplicate inbound priorities")
    result = []
    for rule in raw_rules:
        if rule["direction"] == "Outbound":
            continue
        if rule["direction"] != "Inbound":
            raise PolicyError("Unknown rule direction")
        rule_protocol = rule["protocol"].lower()
        if rule_protocol not in ("all", "*", "tcp", "udp", "icmp", "esp", "ah", "icmpv6"):
            raise PolicyError(f"Unsupported rule protocol: {rule_protocol}")
        if rule_protocol not in (protocol, "all", "*"):
            continue
        if not contains(rule_addresses(rule, "destination", tags), destination):
            continue
        if type(rule["priority"]) is not int or rule["access"] not in ("Allow", "Deny"):
            raise PolicyError("Invalid rule priority or action")
        result.append(Rule(rule["priority"], rule["access"],
                           rule_addresses(rule, "source", tags),
                           ports(rule, "source"), ports(rule, "destination")))
    return sorted(result, key=lambda rule: rule.priority)


def allowed_sources(rules, source_port, destination_port):
    remaining = UNIVERSE
    allowed = []
    for rule in rules:
        if not contains(rule.source_ports, source_port) or not contains(rule.destination_ports, destination_port):
            continue
        matched = intersect(remaining, rule.sources)
        if rule.access == "Allow":
            allowed.extend(matched)
        remaining = subtract(remaining, rule.sources)
        if not remaining:
            break
    if remaining:
        raise PolicyError("Effective NSG response lacks complete default-rule coverage")
    return merge(allowed)


def boundaries(layers, field, maximum):
    points = {0, maximum + 1}
    for rules in layers:
        for rule in rules:
            for low, high in getattr(rule, field):
                if low <= maximum:
                    points.update((low, min(high + 1, maximum + 1)))
    return sorted(points)[:-1]


def check_sources(groups, destination, protocol, destination_port, approved, required, label):
    if not groups:
        return f"{label}: no NSG is attached."
    layers = [compile_rules(group, int(ipaddress.IPv4Address(destination)), protocol) for group in groups]
    # ICMPv4 uses type/code in the NSG source/destination port fields.
    source_points = boundaries(layers, "source_ports", 255 if protocol == "icmp" else 65535)
    destination_points = boundaries(layers, "destination_ports", 255) if protocol == "icmp" else [destination_port]
    if len(source_points) * len(destination_points) > 4096:
        raise PolicyError("Port/type/code policy is too complex for this lab's validator")
    required_allowed = False
    for source_port in source_points:
        for port in destination_points:
            allowed = UNIVERSE
            for rules in layers:
                allowed = intersect(allowed, allowed_sources(rules, source_port, port))
            leaked = subtract(allowed, approved)
            if leaked:
                return (f"{label}: permits sources outside the approved range "
                        f"(for example {ipaddress.IPv4Address(leaked[0][0])}, "
                        f"source/destination port or ICMP type/code {source_port}/{port}).")
            if protocol != "icmp" and contains(allowed, required):
                required_allowed = True
    if protocol == "icmp":
        allowed = UNIVERSE
        for rules in layers:
            allowed = intersect(allowed, allowed_sources(rules, 8, 0))
        required_allowed = contains(allowed, required)
    if not required_allowed:
        return f"{label}: blocks the required source {ipaddress.IPv4Address(required)}."
    return None


def az_json(*arguments):
    try:
        result = subprocess.run(["az", *arguments, "-o", "json"], capture_output=True,
                                text=True, check=True, timeout=90)
    except subprocess.CalledProcessError as error:
        raise PolicyError(f"Azure query failed: {error.stderr.strip()}") from error
    except subprocess.TimeoutExpired as error:
        raise PolicyError("Azure query timed out; effective policy could not be checked") from error
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise PolicyError("Azure returned invalid JSON") from error


def assess(args):
    trusted = ipaddress.IPv4Address(args.trusted_ip)
    if not trusted.is_global:
        raise PolicyError("Bastion SSH must originate from the validation client's public IPv4 address")
    vnet = az_json("network", "vnet", "show", "-g", args.resource_group,
                   "-n", f"vnet-networking-lab-{args.deployment_id}")
    subnets = {item["id"].lower(): item for item in vnet["subnets"]}
    nics = {item["name"]: item for item in az_json("network", "nic", "list", "-g", args.resource_group)}
    vms = {item["name"]: item for item in az_json("vm", "list", "-g", args.resource_group)}
    hosts = {}
    for role in ("bastion", "web", "api", "database"):
        nic = nics[f"nic-{role}-{args.deployment_id}"]
        vm = vms[f"vm-{role}-{args.deployment_id}"]
        interfaces = vm["networkProfile"]["networkInterfaces"]
        configurations = nic["ipConfigurations"]
        if len(interfaces) != 1 or interfaces[0]["id"].lower() != nic["id"].lower() or len(configurations) != 1:
            raise PolicyError("Only the lab's single-NIC, single-IPv4-per-VM topology is supported")
        configuration = configurations[0]
        address = ipaddress.IPv4Address(configuration["privateIPAddress"])
        subnet = subnets[configuration["subnet"]["id"].lower()]
        networks = addresses(values(subnet, "addressPrefix", "addressPrefixes"), {})
        if not networks or not contains(networks, int(address)):
            raise PolicyError(f"Invalid IPv4 subnet for {role}")
        effective = az_json("network", "nic", "list-effective-nsg", "--ids", nic["id"])
        if effective.get("nextLink") or not isinstance(effective.get("value"), list):
            raise PolicyError("Incomplete effective NSG response")
        hosts[role] = {"ip": str(address), "subnet": networks, "groups": effective["value"]}
    bastion = hosts["bastion"]
    api = hosts["api"]
    checks = [
        ("bastion", "tcp", 22, [(int(trusted), int(trusted))], int(trusted), "Bastion SSH"),
        *[(role, "tcp", 22, bastion["subnet"], int(ipaddress.IPv4Address(bastion["ip"])), f"{role} SSH")
          for role in ("web", "api", "database")],
        ("database", "tcp", 5432, api["subnet"], int(ipaddress.IPv4Address(api["ip"])), "Database TCP 5432"),
        ("web", "icmp", None, bastion["subnet"], int(ipaddress.IPv4Address(bastion["ip"])), "Web ICMP"),
    ]
    failures = []
    for role, protocol, port, approved, required, label in checks:
        host = hosts[role]
        failure = check_sources(host["groups"], host["ip"], protocol, port, approved, required, label)
        if failure:
            failures.append(failure)
    if failures:
        print(f"Trusted bastion SSH source: {trusted}/32. " + " ".join(failures))
        return 1
    print(f"Effective inbound source restrictions match the policy; bastion SSH is limited to {trusted}/32.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resource-group", required=True)
    parser.add_argument("--deployment-id", required=True)
    parser.add_argument("--trusted-ip", required=True)
    try:
        return assess(parser.parse_args())
    except (PolicyError, OSError, KeyError, TypeError, AttributeError, ValueError) as error:
        print(f"Cannot assess effective NSG policy: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
