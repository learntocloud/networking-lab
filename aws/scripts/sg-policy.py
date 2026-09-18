#!/usr/bin/env python3
"""Assess effective AWS security-group ingress sources for the lab hardening policy.

Security groups are stateful, allow-only, unordered, and additive across every
group attached to an interface. This evaluator therefore unions the sources of
all matching rules on all attached groups, expands security-group references to
the private IPs of the interfaces that currently hold those groups, resolves
managed prefix lists, and compares the result with the approved source set.
"""

import argparse
import ipaddress
import json
import subprocess
import sys


class PolicyError(ValueError):
    pass


ROLES = ("bastion", "web", "api", "database")
PROTOCOL_NUMBERS = {"tcp": {"tcp", "6"}, "icmp": {"icmp", "1"}}


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
            if cursor > high:
                break
        if cursor <= high:
            result.append((cursor, high))
    return result


def contains(ranges, address):
    return any(low <= address <= high for low, high in ranges)


def cidr_range(value):
    network = ipaddress.ip_network(value, strict=False)
    if network.version != 4:
        return None
    return (int(network.network_address), int(network.broadcast_address))


def aws_json(args, *arguments):
    try:
        result = subprocess.run(
            ["aws", "--region", args.region, "--output", "json", *arguments],
            check=True, capture_output=True, text=True, timeout=90,
        )
    except subprocess.CalledProcessError as error:
        raise PolicyError(f"AWS query failed: {error.stderr.strip()}") from error
    except subprocess.TimeoutExpired as error:
        raise PolicyError("AWS query timed out") from error
    except FileNotFoundError as error:
        raise PolicyError("The aws CLI is not installed") from error
    try:
        return json.loads(result.stdout or "null")
    except json.JSONDecodeError as error:
        raise PolicyError("AWS returned invalid JSON") from error


def describe_hosts(args):
    ids = [getattr(args, role) for role in ROLES]
    reservations = aws_json(args, "ec2", "describe-instances", "--instance-ids", *ids)["Reservations"]
    instances = {vm["InstanceId"]: vm for item in reservations for vm in item["Instances"]}
    hosts = {}
    for role, instance_id in zip(ROLES, ids):
        vm = instances.get(instance_id)
        if vm is None:
            raise PolicyError(f"Cannot identify the {role} instance {instance_id}")
        if vm["State"]["Name"] != "running":
            raise PolicyError(f"The {role} instance is not running")
        if vm.get("VpcId") != args.vpc_id:
            raise PolicyError(f"The {role} instance is not in the lab VPC")
        nics = vm.get("NetworkInterfaces", [])
        if (len(nics) != 1 or nics[0].get("Ipv6Addresses") or
                len(nics[0].get("PrivateIpAddresses", [])) != 1):
            raise PolicyError("Only the lab single-interface, primary-IPv4 topology is supported")
        hosts[role] = {
            "ip": int(ipaddress.IPv4Address(nics[0]["PrivateIpAddress"])),
            "groups": [group["GroupId"] for group in nics[0].get("Groups", [])],
        }
        if not hosts[role]["groups"]:
            raise PolicyError(f"The {role} interface has no security group")
    return hosts


def group_members(args):
    """Private IPv4 addresses of every interface in the VPC, keyed by security group."""
    vpc = aws_json(args, "ec2", "describe-vpcs", "--vpc-ids", args.vpc_id)["Vpcs"][0]
    if any(item.get("Ipv6CidrBlockState", {}).get("State") not in (None, "disassociated")
           for item in vpc.get("Ipv6CidrBlockAssociationSet", [])):
        raise PolicyError("Dual-stack VPCs are outside this lab validator's scope")
    interfaces = aws_json(args, "ec2", "describe-network-interfaces",
                          "--filters", f"Name=vpc-id,Values={args.vpc_id}")["NetworkInterfaces"]
    members = {}
    for interface in interfaces:
        if interface.get("Ipv6Addresses"):
            raise PolicyError("Dual-stack interfaces are outside this lab validator's scope")
        addresses = [cidr_range(item["PrivateIpAddress"]) for item in interface.get("PrivateIpAddresses", [])]
        for group in interface.get("Groups", []):
            members.setdefault(group["GroupId"], []).extend(addresses)
    return {group: merge(addresses) for group, addresses in members.items()}


def prefix_list_ranges(args, prefix_list_id, cache):
    if prefix_list_id not in cache:
        entries = aws_json(args, "ec2", "get-managed-prefix-list-entries",
                           "--prefix-list-id", prefix_list_id).get("Entries", [])
        ranges, ipv6 = [], False
        for entry in entries:
            value = cidr_range(entry["Cidr"])
            if value is None:
                ipv6 = True
            else:
                ranges.append(value)
        cache[prefix_list_id] = (merge(ranges), ipv6)
    return cache[prefix_list_id]


def rule_sources(args, rule, members, prefix_cache, account):
    ranges, ipv6 = [], bool(rule.get("Ipv6Ranges"))
    for item in rule.get("IpRanges", []):
        value = cidr_range(item["CidrIp"])
        if value is None:
            raise PolicyError(f"Invalid IPv4 source {item['CidrIp']}")
        ranges.append(value)
    for item in rule.get("PrefixListIds", []):
        listed, listed_ipv6 = prefix_list_ranges(args, item["PrefixListId"], prefix_cache)
        ranges.extend(listed)
        ipv6 = ipv6 or listed_ipv6
    for pair in rule.get("UserIdGroupPairs", []):
        if (pair.get("VpcPeeringConnectionId") or pair.get("PeeringStatus") or
                (pair.get("UserId") and pair["UserId"] != account) or
                pair.get("VpcId") not in (None, args.vpc_id)):
            raise PolicyError("Cross-account or peered security-group references are outside this lab validator's scope")
        group_id = pair.get("GroupId")
        if not group_id:
            raise PolicyError("Security-group reference without a group ID")
        ranges.extend(members.get(group_id, []))
    return merge(ranges), ipv6


def rule_matches(rule, protocol, port):
    value = str(rule["IpProtocol"]).lower()
    if value == "-1":
        return True
    if value not in PROTOCOL_NUMBERS[protocol]:
        return False
    if protocol == "icmp":
        return True
    low, high = rule.get("FromPort"), rule.get("ToPort")
    if type(low) is not int or type(high) is not int or not 0 <= low <= high <= 65535:
        raise PolicyError("Invalid security-group port range")
    return low <= port <= high


def rule_allows_echo(rule):
    value = str(rule["IpProtocol"]).lower()
    if value == "-1":
        return True
    if value not in PROTOCOL_NUMBERS["icmp"]:
        return False
    return rule.get("FromPort", -1) in (-1, 8) and rule.get("ToPort", -1) in (-1, 0)


def effective_sources(args, groups, protocol, port, required_filter, members, prefix_cache, account):
    """Union of sources allowed on any attached group; also the union for the required traffic."""
    allowed, required_allowed, ipv6 = [], [], False
    for group in groups:
        if group["VpcId"] != args.vpc_id:
            raise PolicyError(f"Security group {group['GroupId']} is not in the lab VPC")
        for rule in group.get("IpPermissions", []):
            if not rule_matches(rule, protocol, port):
                continue
            sources, rule_ipv6 = rule_sources(args, rule, members, prefix_cache, account)
            allowed.extend(sources)
            ipv6 = ipv6 or rule_ipv6
            if required_filter(rule):
                required_allowed.extend(sources)
    return merge(allowed), merge(required_allowed), ipv6


def assess(args):
    trusted = ipaddress.IPv4Address(args.trusted_ip)
    if not trusted.is_global:
        raise PolicyError("Bastion SSH must originate from the validation client's public IPv4 address")
    account = aws_json(args, "sts", "get-caller-identity")["Account"]
    hosts = describe_hosts(args)
    members = group_members(args)
    group_ids = sorted({group for host in hosts.values() for group in host["groups"]})
    described = {group["GroupId"]: group for group in
                 aws_json(args, "ec2", "describe-security-groups", "--group-ids", *group_ids)["SecurityGroups"]}
    if set(described) != set(group_ids):
        raise PolicyError("Could not describe every attached security group")
    for role, host in hosts.items():
        host["groups"] = [described[group] for group in host["groups"]]
    prefix_cache = {}
    bastion, api = hosts["bastion"], hosts["api"]
    checks = [
        ("bastion", "tcp", 22, [(int(trusted), int(trusted))], int(trusted), "Bastion SSH"),
        *[(role, "tcp", 22, [(bastion["ip"], bastion["ip"])], bastion["ip"], f"{role} SSH")
          for role in ("web", "api", "database")],
        ("database", "tcp", 5432, [(api["ip"], api["ip"])], api["ip"], "Database TCP 5432"),
        ("web", "icmp", None, [(bastion["ip"], bastion["ip"])], bastion["ip"], "Web ICMP"),
    ]
    failures = []
    for role, protocol, port, approved, required, label in checks:
        required_filter = rule_allows_echo if protocol == "icmp" else (lambda rule: True)
        allowed, required_allowed, ipv6 = effective_sources(
            args, hosts[role]["groups"], protocol, port, required_filter, members, prefix_cache, account)
        leaked = subtract(allowed, approved)
        if leaked:
            failures.append(f"{label} permits unauthorized source {ipaddress.IPv4Address(leaked[0][0])} "
                            "across the attached security groups.")
        if ipv6:
            failures.append(f"{label} permits IPv6 sources; the lab policy is IPv4-only.")
        if not contains(required_allowed, required):
            failures.append(f"{label} blocks its required source.")
    if failures:
        print("Bastion SSH must be restricted to the current client's public IPv4 /32; "
              "internal SSH, database, and ICMP sources must resolve to the bastion or API only. "
              + " ".join(failures))
        return 1
    print("Effective security-group ingress sources match the policy; bastion SSH is limited to the current client's public IPv4 /32.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--region", required=True)
    parser.add_argument("--vpc-id", required=True)
    parser.add_argument("--trusted-ip", required=True)
    for role in ROLES:
        parser.add_argument(f"--{role}", required=True, help=f"{role} EC2 instance ID")
    try:
        return assess(parser.parse_args())
    except (PolicyError, OSError, KeyError, TypeError, AttributeError, ValueError, IndexError) as error:
        print(f"Cannot assess effective security-group policy: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
