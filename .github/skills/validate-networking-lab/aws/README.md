# AWS Validation Scripts

These scripts validate the AWS version of the networking lab.

## Scripts

| Script | Purpose |
|--------|---------|
| `common.sh` | Shared setup (terraform outputs, SSH config) |
| `diagnose.sh` | Test all 4 incidents |
| `fix-inc-4521.sh` | Fix NAT Gateway (associate with route table) |
| `fix-inc-4522.sh` | Fix Route 53 Private Zone (VPC association + records) |
| `fix-inc-4523.sh` | Fix Security Groups (inbound rules) |
| `fix-inc-4524.sh` | Fix Security Hardening (source restrictions) |
| `test-validation.sh` | Test validate.sh and token generation |
| `run-full-validation.sh` | Deploy, fix, validate, and destroy |

## AWS Equivalents

| Concept | Azure | AWS |
|---------|-------|-----|
| NAT | NAT Gateway + Subnet Association | NAT Gateway + Route Table |
| Private DNS | Private DNS Zone + VNet Link | Route 53 Private Hosted Zone + VPC Association |
| Firewall | NSG Rules | Security Group Rules |
| CLI | `az network` | `aws ec2` |
