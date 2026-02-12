---
name: validate-networking-lab
description: Validates the networking lab by going through the actual student journey - SSHing through bastion, running real connectivity tests, fixing issues with cloud CLI, and verifying each incident is resolved. Supports Azure, AWS, and GCP.
---

# Validate Networking Lab

Test the lab like a student would: diagnose via SSH, fix with cloud CLI, verify.

## Prerequisites

- SSH key will be auto-generated at `~/.ssh/netlab-key`
- Cloud CLI logged in (az/aws/gcloud)

## Run Validation

The validation script will automatically deploy, test, and destroy the lab.

### Azure

```bash
cd /home/gps/Developer/networking-lab/.github/skills/validate-networking-lab/azure/scripts
chmod +x *.sh
./run-full-validation.sh
```

Options:
- `--skip-deploy`: Skip deployment (use existing infrastructure)

### AWS

```bash
cd /home/gps/Developer/networking-lab/.github/skills/validate-networking-lab/aws/scripts
chmod +x *.sh
./run-full-validation.sh
```

Options:
- `--skip-deploy`: Skip deployment (use existing infrastructure)

### GCP (Coming Soon)

```bash
cd /home/gps/Developer/networking-lab/.github/skills/validate-networking-lab/gcp/scripts
chmod +x *.sh
./run-full-validation.sh
```

## What It Does

1. **Deploy Infrastructure** - Runs terraform apply to create the broken lab environment
2. **Initial Diagnosis** - SSHs through bastion, tests all 4 incidents (should all fail initially)
3. **Fix INC-4521** - Applies NAT gateway fix + verifies with validate.sh
4. **Fix INC-4522** - Applies DNS fix + verifies with validate.sh
5. **Fix INC-4523** - Applies NSG ports fix + verifies with validate.sh
6. **Fix INC-4524** - Applies security hardening fix + verifies with validate.sh
7. **Final Validation** - Confirms all 4 incidents resolved
8. **Token Test** - Verifies token generation and tamper detection
9. **Cleanup** - Destroys ALL resources by deleting the resource group (mandatory)

## Expected Output

```
╔══════════════════════════════════════════════════════════════╗
║                    VALIDATION SUMMARY                        ║
╚══════════════════════════════════════════════════════════════╝

┌────────────────────────────────────┬──────────┐
│ Step                               │ Result   │
├────────────────────────────────────┼──────────┤
│ Deploy Infrastructure              │ ✓ PASS   │
│ Initial Diagnosis                  │ ✓ PASS   │
│ Fix INC-4521 (NAT Gateway)         │ ✓ PASS   │
│ Fix INC-4522 (DNS)                 │ ✓ PASS   │
│ Fix INC-4523 (NSG Ports)           │ ✓ PASS   │
│ Fix INC-4524 (Security)            │ ✓ PASS   │
│ Final Validation                   │ ✓ PASS   │
│ Token Generation Test              │ ✓ PASS   │
└────────────────────────────────────┴──────────┘

══════════════════════════════════════════════════════════════
  ALL TESTS PASSED (8/8)
  Lab validation complete - ready for student use
══════════════════════════════════════════════════════════════
```

Exit code 0 = all passed, exit code 1 = something failed.

## Incidents Overview

| Incident | Concept | Azure | AWS | GCP |
|----------|---------|-------|-----|-----|
| INC-4521 | NAT/Internet Egress | NAT Gateway + Subnet | NAT Gateway + Route Table | Cloud NAT + Router |
| INC-4522 | Private DNS | Private DNS Zone + VNet Link | Route 53 Private Zone + VPC Association | Cloud DNS Private Zone |
| INC-4523 | Firewall Rules | NSG Rules | Security Groups | Firewall Rules |
| INC-4524 | Security Hardening | NSG Source Restrictions | SG Source Restrictions | Firewall Source Restrictions |

## Important: Complete Resource Cleanup

**All resources must be destroyed after completing the lab to avoid ongoing costs.**

The validation script automatically destroys all resources by deleting the entire resource group. This ensures complete cleanup regardless of how fixes were applied (Terraform, CLI commands, Azure Portal, etc.).

### Why Resource Group Deletion?

Students may fix the lab issues using different methods than the provided scripts:
- Direct Azure Portal changes  
- Alternative CLI commands
- Custom Terraform modifications
- ARM templates or Bicep

**Deleting the resource group (`az group delete`) destroys ALL contained resources**, guaranteeing no orphaned resources remain.

### Manual Cleanup

If you need to manually destroy the lab:

```bash
# Get the resource group name from terraform state
cd azure/terraform
RESOURCE_GROUP=$(terraform output -raw resource_group_name)

# Delete the entire resource group (destroys EVERYTHING)
az group delete -n "$RESOURCE_GROUP" --yes

# Clean up local files
rm -f ~/.ssh/netlab-key
rm -f terraform.tfstate terraform.tfstate.backup
```

### Cost Warning

If cleanup fails or is interrupted, verify no resources remain:
```bash
az group list --query "[?starts_with(name, 'rg-networking-lab')]" -o table
```

Delete any remaining groups manually to avoid unexpected charges.

## Note

The scripts in `<cloud>/scripts/` contain solutions and are git-ignored.
