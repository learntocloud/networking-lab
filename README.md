# Networking Lab

Fix a deliberately broken Azure network infrastructure. Learn by troubleshooting.

```
┌────────────────────────────────────────────────────────────────┐
│                    VNet (10.0.0.0/16)                          │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐   │
│  │ Public Subnet  │  │ Private Subnet │  │    Database    │   │
│  │  10.0.1.0/24   │──│  10.0.2.0/24   │──│    Subnet      │   │
│  │   - Bastion    │  │   - Web App    │  │  10.0.3.0/24   │   │
│  │   - NAT GW     │  │   - API Server │  │                │   │
│  └────────────────┘  └────────────────┘  └────────────────┘   │
└────────────────────────────────────────────────────────────────┘
```

## Quick Start

```bash
cd networking-lab/azure/terraform
terraform init && terraform apply

# Save SSH key and set environment variables
terraform output -raw ssh_private_key > ~/.ssh/netlab-key && chmod 600 ~/.ssh/netlab-key
export RESOURCE_GROUP=$(terraform output -raw resource_group_name)
export DEPLOYMENT_ID=$(terraform output -raw deployment_id)
export VNET_NAME="vnet-networking-lab-${DEPLOYMENT_ID}"

# Get connection info
terraform output connection_instructions
```

**Cost**: ~$0.50-1.00/session. Run `terraform destroy` when done.

---

# Tasks

Work through in order. Validate with `../scripts/validate.sh [task-1|task-2|task-3|task-4|all]`

## Task 1: Routing & Gateways

**Problem**: API server can't reach the internet.

SSH to bastion → SSH to API server → test with `curl -I https://example.com`

The NAT Gateway exists but something's missing. Use `az network nat gateway list` and `az network vnet subnet show` to investigate.

<details><summary>Hint</summary>The NAT Gateway exists but isn't attached to anything. Subnets need to be associated with it.</details>

---

## Task 2: DNS Resolution

**Problem**: Internal hostnames (`api.internal.local`, `db.internal.local`) don't resolve.

From any VM, test with `nslookup api.internal.local 168.63.129.16`

The Private DNS Zone exists but isn't usable. Check `az network private-dns zone list`, `az network private-dns link vnet list`, and `az network private-dns record-set a list`.

<details><summary>Hint</summary>A Private DNS Zone needs two things to work: a connection to the VNet, and actual DNS records.</details>

---

## Task 3: Ports & Protocols

**Problem**: Web server can't reach API (port 8080). API can't reach database (port 5432).

Test with `nc -zv <ip> <port> -w 3`

NSG rules control this. Check them with `az network nsg rule list --nsg-name nsg-api-${DEPLOYMENT_ID}` and `nsg-database-${DEPLOYMENT_ID}`.

<details><summary>Hint</summary>NSG rule priorities matter (lower = first). One NSG has a blocking rule. Another has the wrong access type.</details>

---

## Task 4: Security Hardening

**Problem**: Infrastructure is too permissive. Lock it down.

Issues to fix:
- SSH open to internet (should be bastion subnet 10.0.1.0/24 only)
- Database accessible from entire VNet (should be API subnet 10.0.2.0/24 only)
- ICMP open from anywhere

Audit all NSGs. Update source address prefixes.

<details><summary>Hint</summary>Azure's default AllowVnetInBound (priority 65000) allows all VNet traffic. You need an explicit deny rule for the database.</details>

---

# Completion

```bash
../scripts/validate.sh all
../scripts/validate.sh export  # generates completion token
```

Use your **learntocloud.guide GitHub username** when prompted. Submit token at https://learntocloud.guide/verify

**Cleanup**: `terraform destroy`

---

## Troubleshooting

**DNS caching**: Query Azure DNS directly: `nslookup host 168.63.129.16`

**Database not listening**: The database subnet has no internet access by design. Start a test listener: `nohup nc -lk 5432 &`

**Task 4 still failing**: Did you add an explicit deny rule? The default AllowVnetInBound bypasses source restrictions.

## Resources

- [Azure VNet](https://learn.microsoft.com/en-us/azure/virtual-network/)
- [Azure NSG](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview)
- [Azure Private DNS](https://learn.microsoft.com/en-us/azure/dns/private-dns-overview)
