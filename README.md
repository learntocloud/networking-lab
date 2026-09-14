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

## Having Trouble?

Please use **GitHub Issues** for bugs, broken instructions, or unclear steps:

- Open an issue: [GitHub Issues](issues/new/choose)
- Include: cloud/provider, which incident/step you’re on, what you expected vs what happened, and the output of the validation script (redact secrets/tokens).

## Cost

~$0.50–1.00 per session. Always destroy resources when done.

## Contributing

The infrastructure is **intentionally misconfigured** — that is the point of the lab. Students fix issues using the cloud provider CLI (`az`, `aws`, `gcloud`), not by editing Terraform. When contributing, do not "fix" broken resources in the Terraform code. If you discover a teardown issue, the right place to address it is in the provider's `destroy.sh` script or in a README troubleshooting note, not by modifying the Terraform modules.

### Private DNS naming

All providers use `internal.test` for the lab's private DNS zone. `.test` is [reserved for testing](https://www.rfc-editor.org/rfc/rfc6761.html#section-6.2) and uses normal application DNS lookups when the private DNS server is configured to answer for it. Avoid `.local`: Ubuntu reserves it for multicast DNS by default, and [Azure recommends against using it for private DNS zones](https://learn.microsoft.com/en-us/azure/dns/private-dns-overview).

INC-4522 requires correct cloud DNS answers and successful system-resolver lookups on the web, API, and database VMs. The shared check in `scripts/dns-validation.sh` uses the provider's SSH helper; cloud DNS is queried from the web VM, where DNS tools are installed. System lookups use `getent ahostsv4`, without requiring DNS tools on the API VM. This keeps DNS independent of the intentional port restrictions in INC-4523.

Run the offline DNS regression checks with `bash tests/dns-validation.sh`. They mock SSH and DNS commands; they do not deploy cloud resources or replace live lab validation.
