# Networking Lab

Fix deliberately broken cloud network infrastructure. Learn by troubleshooting real incidents.

## Choose Your Cloud

| Provider | Status | Guide |
|----------|--------|-------|
| Azure | ✅ Available | [azure/README.md](azure/README.md) |
| AWS | ✅ Available | [aws/README.md](aws/README.md) |
| GCP | 🚧 Coming soon | — |

## What You'll Learn

- **Routing & Gateways** — NAT gateways, route tables, internet egress
- **DNS Resolution** — Private DNS zones, service discovery
- **Network Security** — Security groups, firewall rules, subnet isolation
- **Troubleshooting** — Real-world diagnostic techniques

## How It Works

- Infrastructure deploys with intentional misconfigurations
- Incident tickets describe symptoms — you find the fix
- Diagnose issues by SSHing into VMs through a bastion host
- Fix issues from your local machine using cloud provider CLI (az, aws, gcloud)
- Validate fixes from your local machine — the script tests connectivity via SSH

## Cost

~$0.50–1.00 per session. Always destroy resources when done.
