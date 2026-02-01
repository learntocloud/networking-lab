# GCP Validation Scripts

🚧 **Coming Soon**

These scripts will validate the GCP version of the networking lab.

## Expected Scripts

| Script | Purpose |
|--------|---------|
| `common.sh` | Shared setup (terraform outputs, SSH config) |
| `diagnose.sh` | Test all 4 incidents |
| `fix-inc-4521.sh` | Fix Cloud NAT (configure router) |
| `fix-inc-4522.sh` | Fix Cloud DNS Private Zone (VPC binding + records) |
| `fix-inc-4523.sh` | Fix Firewall Rules (allow rules) |
| `fix-inc-4524.sh` | Fix Security Hardening (source ranges) |
| `test-validation.sh` | Test validate.sh and token generation |

## GCP Equivalents

| Concept | Azure | GCP |
|---------|-------|-----|
| NAT | NAT Gateway + Subnet Association | Cloud NAT + Cloud Router |
| Private DNS | Private DNS Zone + VNet Link | Cloud DNS Private Zone + VPC Binding |
| Firewall | NSG Rules | VPC Firewall Rules |
| CLI | `az network` | `gcloud compute` |
