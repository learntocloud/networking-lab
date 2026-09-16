# Networking Lab

Fix deliberately broken cloud network infrastructure. Learn by troubleshooting real incidents.

## Choose Your Cloud

| Provider | Status | Guide |
|----------|--------|-------|
| Azure | ✅ Available | [azure/README.md](azure/README.md) |
| AWS | ✅ Available | [aws/README.md](aws/README.md) |
| GCP | ✅ Available | [gcp/README.md](gcp/README.md) |

## What You'll Learn

- **Routing & Gateways** — NAT gateways, route tables, internet egress
- **DNS Resolution** — Private DNS zones, service discovery
- **Network Security** — Security groups, firewall rules, subnet isolation
- **Troubleshooting** — Real-world diagnostic techniques

## How It Works

1. **Deploy** — Run the setup script. Infrastructure deploys with intentional misconfigurations.
2. **Read the incidents** — Ticket descriptions tell you the symptoms. Your job is to find the root cause.
3. **Diagnose** — SSH through the bastion host into VMs to test connectivity, check DNS, inspect services, etc.
4. **Fix** — From your local terminal, use the cloud provider CLI (`az`, `aws`, `gcloud`) to fix the misconfigured cloud resources (routes, firewall rules, DNS records, etc.). You are not editing Terraform or fixing things from inside the VMs.
5. **Validate** — Run the validation script from your local machine. It SSHes into the VMs and runs real connectivity checks.
6. **Clean up** — Run the provider's destroy script when finished.

## Having Trouble?

Please use **GitHub Issues** for bugs, broken instructions, or unclear steps:

- Open an issue: [GitHub Issues](https://github.com/learntocloud/networking-lab/issues/new/choose)
- Include: cloud/provider, which incident/step you’re on, what you expected vs what happened, and the output of the validation script (redact secrets/tokens).

## Contributing

Preserve the **intentional misconfigurations** that make up the challenges. Students resolve them using the cloud provider CLI (`az`, `aws`, `gcloud`), not by editing Terraform.

Fix unintended infrastructure, setup, validation, or teardown bugs at their source, including Terraform when appropriate. Changes should keep the intended faults reproducible and the lab deployable and removable.
