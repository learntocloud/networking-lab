# Azure Networking Lab

Deliberately broken Azure network infrastructure. Deploy, troubleshoot, and validate four tasks.

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

## Repo Layout

- `scripts/`
  - `setup.sh` – deploy broken lab via Terraform
  - `validate.sh` – connectivity-based validation + token export
  - `destroy.sh` – teardown and cleanup
- `terraform/`
  - `main.tf`, `variables.tf`, `outputs.tf`
  - `modules/`
    - `network/` – VNets, subnets, NSGs, routes, NAT
    - `dns/` – Private DNS zone, records, links
    - `compute/` – Bastion, web, API, database VMs (cloud-init templates)
  - `broken-state/` – known-bad configs for learning

## Prerequisites

- Azure CLI logged in (`az login`)
- Terraform
- `jq`, `bash`, `ssh`
- Permissions to create network + compute resources

## Setup

```bash
cd azure/scripts
./setup.sh
```

Manual (optional):
```bash
cd azure/terraform
terraform init && terraform apply
terraform output -raw ssh_private_key > ~/.ssh/netlab-key && chmod 600 ~/.ssh/netlab-key
```

Set envs (used by validation & Azure CLI commands):
```bash
cd azure/terraform
export RESOURCE_GROUP=$(terraform output -raw resource_group_name)
export DEPLOYMENT_ID=$(terraform output -raw deployment_id)
export VNET_NAME="vnet-networking-lab-${DEPLOYMENT_ID}"
```

## Validation

```bash
cd azure/scripts
./validate.sh [task-1|task-2|task-3|task-4|all|export|verify]
```

- `task-1` Routing/NAT: API can `curl -I https://example.com`
- `task-2` DNS: `nslookup api.internal.local 168.63.129.16` returns 10.x.x.x
- `task-3` Ports: `nc -zw3 $API_IP 8080` and `nc -zw3 $DB_IP 5432` => `1`
- `task-4` Security: SSH restricted; DB only from API subnet; bastion→DB blocked; ICMP restricted
- `export`: generate completion token
- `verify <token>`: verify token

## Tasks (Detailed)

### Task 1: Routing & Gateways
- **Problem**: API server lacks internet egress.
- **Check**: NAT Gateway exists but not attached to private subnet.
- **Commands**: `az network nat gateway list`, `az network vnet subnet show -g $RESOURCE_GROUP --vnet-name $VNET_NAME -n <subnet>`
- **Fix**: Associate NAT Gateway to private subnet.

### Task 2: DNS Resolution
- **Problem**: `*.internal.local` does not resolve.
- **Check**: Private DNS zone exists; ensure VNet link + A records for web/api/db.
- **Commands**: `az network private-dns zone list`, `... link vnet list`, `... record-set a list`
- **Fix**: Link zone to VNet; add A records pointing to 10.x.x.x addresses.

### Task 3: Ports & Protocols
- **Problem**: Web→API (8080) and API→DB (5432) blocked.
- **Check**: NSG rules and priorities on `nsg-api-${DEPLOYMENT_ID}` and `nsg-database-${DEPLOYMENT_ID}`.
- **Commands**: `az network nsg rule list --nsg-name nsg-api-${DEPLOYMENT_ID}`; same for database.
- **Fix**: Ensure allow rules exist with lower priority than denies; correct access type.

### Task 4: Security Hardening
- **Problem**: Overly permissive traffic.
- **Checks/Fixes**:
  - SSH to web/API limited to bastion subnet `10.0.1.0/24` (rule `allow-ssh`).
  - DB access only from API subnet `10.0.2.0/24` (rule `postgres-access`). Add explicit deny for others (default AllowVnetInBound is broad).
  - Bastion must NOT reach DB (validate via `nc` from bastion).
  - ICMP not open to internet; restrict/remove `allow-icmp`.

## Troubleshooting

- **DNS caching**: query Azure DNS directly: `nslookup host 168.63.129.16`
- **Nested SSH**: keep inner SSH options simple; see `validate.sh`
- **Netcat listener**: `nohup nc -lk 5432 &` on DB VM to test connectivity
- **Strip newlines**: `... | tr -d '\n\r'` for validation comparisons

## Cleanup

```bash
cd azure/scripts
./destroy.sh
```

(or `terraform destroy` and `rm ~/.ssh/netlab-key`)

## Completion

```bash
cd azure/scripts
./validate.sh export
```
Submit token at https://learntocloud.guide/verify using your learntocloud.guide GitHub username.

**Cost**: ~$0.50-1.00/session. Remember to destroy when done.
