# Copilot Instructions

## Repository Overview

This is the **Networking Lab** — a hands-on cloud networking troubleshooting exercise. Students deploy intentionally broken infrastructure and fix four realistic incident tickets (INC-4521 to INC-4524) across Azure, AWS, and GCP.

## Repository Structure

```
networking-lab/
├── azure/                  # Azure cloud provider lab
│   ├── terraform/          # Terraform infrastructure (modules: network, compute, dns)
│   └── scripts/            # setup.sh, validate.sh, destroy.sh
├── aws/                    # AWS cloud provider lab
│   ├── terraform/          # Terraform infrastructure (modules: network, compute, dns)
│   └── scripts/            # setup.sh, validate.sh, destroy.sh
├── gcp/                    # GCP cloud provider lab
│   ├── terraform/          # Terraform infrastructure (modules: network, compute, dns)
│   └── scripts/            # setup.sh, validate.sh, destroy.sh
└── .github/
    ├── copilot-instructions.md
    └── skills/
        └── validate-networking-lab/  # Skill for end-to-end lab validation
```

## Incident Structure

Each cloud provider implements the same four incidents:

| Incident | Title | Concept |
|----------|-------|---------|
| INC-4521 | API service can't pull external data | NAT gateway / internet egress |
| INC-4522 | Service discovery broken | Private DNS zones |
| INC-4523 | Web frontend can't reach backend | Firewall rules / security groups / NSG rules |
| INC-4524 | Security audit findings | Security hardening (source restrictions) |

## Key Conventions

### Terraform

- Minimum Terraform version: `>= 1.0`
- Infrastructure is organized into three modules per provider: `network`, `compute`, `dns`
- Resources use a `deployment_id` (random hex) suffix for uniqueness
- Tags always include `project = "networking-lab"` and `purpose = "learning"`
- The infrastructure is **intentionally misconfigured** — broken configurations are the learning content; do not "fix" them in Terraform unless you are adding a new incident

### Shell Scripts

- `setup.sh` — deploy infrastructure with `terraform apply` and display SSH connection instructions
- `validate.sh` — test actual connectivity by SSHing through the bastion host; accepts `export` argument for token generation
- `destroy.sh` — tear down all resources

### Cloud Provider Specifics

- **Azure**: Uses NSGs, Private DNS Zones, NAT Gateway; resource group named `rg-networking-lab-<id>`
- **AWS**: Uses Security Groups, Route 53 Private Hosted Zones, NAT Gateway
- **GCP**: Uses Firewall Rules, Cloud DNS Private Zones, Cloud NAT + Cloud Router

## How to Validate Changes

Use the `validate-networking-lab` skill (`.github/skills/validate-networking-lab/`) for end-to-end validation. It deploys the lab, confirms all incidents are broken initially, applies each fix, verifies connectivity, and cleans up.

Do not run validation manually — always use `./validate.sh` from the appropriate `<cloud>/scripts/` directory.

## Important: Solution Scripts Are Git-Ignored

The skill solution scripts (`.github/skills/**/scripts/`) contain the answers and are excluded from the repository via `.gitignore`. Do not commit solution scripts.

## Cost

Each session costs approximately $0.50–$1.00. Always destroy resources when done with `./destroy.sh`.
