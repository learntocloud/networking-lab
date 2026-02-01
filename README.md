# Networking Lab

Fix deliberately broken cloud network infrastructure. Learn by troubleshooting real incidents.

## Choose Your Cloud

| Provider | Status | Guide |
|----------|--------|-------|
| Azure | ✅ Available | [azure/README.md](azure/README.md) |
| AWS | 🚧 Coming soon | — |
| GCP | 🚧 Coming soon | — |

## What You'll Learn

- **Routing & Gateways** — NAT gateways, route tables, internet egress
- **DNS Resolution** — Private DNS zones, service discovery
- **Network Security** — Security groups, firewall rules, subnet isolation
- **Troubleshooting** — Real-world diagnostic techniques

## How It Works

1. Deploy a broken infrastructure with intentional misconfigurations
2. Receive incident tickets describing symptoms (not root causes)
3. SSH into VMs and diagnose using standard networking tools
4. Fix issues via CLI
5. Validate fixes and export a completion token

## Completion

After resolving all incidents, generate a token containing your GitHub username:

```bash
./validate.sh export
```

## Cost

~$0.50–1.00 per session. Always destroy resources when done.
