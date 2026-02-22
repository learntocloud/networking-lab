#!/bin/bash
# =============================================================================
# NETWORKING LAB - DESTROY SCRIPT
# Tears down all infrastructure to avoid ongoing costs
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${RED}============================================${NC}"
echo -e "${RED}   NETWORKING LAB - DESTROY${NC}"
echo -e "${RED}============================================${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will destroy ALL lab resources!${NC}"
echo ""

# Check if state exists
if [ ! -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
    echo "No terraform state found. Nothing to destroy."
    exit 0
fi

# Get resource group for confirmation
cd "$TERRAFORM_DIR"
RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "unknown")
DEPLOYMENT_ID=$(terraform output -raw deployment_id 2>/dev/null || echo "unknown")

echo "Resource group to destroy: $RESOURCE_GROUP"
echo ""
read -p "Are you sure you want to destroy all resources? (yes/N) " -r
echo ""

if [[ ! $REPLY == "yes" ]]; then
    echo "Aborted. Type 'yes' (not just 'y') to confirm destruction."
    exit 0
fi

# -----------------------------------------------------------------------------
# Pre-cleanup: remove out-of-band resources created by students during the lab
# so that terraform destroy does not fail on dependent/nested resources.
# -----------------------------------------------------------------------------

echo "Cleaning up student-created resources..."

# INC-4522: Students create a VNet link on the private DNS zone via:
#   az network private-dns link vnet create ...
# Terraform does not manage this link, so it must be removed before terraform
# tries to delete the DNS zone, otherwise Azure returns 409 Conflict.
DNS_ZONE="internal.local"
VNET_LINK="LabVNetLink"
if az network private-dns link vnet show \
    --resource-group "$RESOURCE_GROUP" \
    --zone-name "$DNS_ZONE" \
    --name "$VNET_LINK" &>/dev/null; then
    echo "  Removing DNS VNet link '$VNET_LINK' from zone '$DNS_ZONE'..."
    az network private-dns link vnet delete \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$DNS_ZONE" \
        --name "$VNET_LINK" \
        --yes
    echo -e "  ${GREEN}✓${NC} DNS VNet link removed"
else
    echo -e "  ${GREEN}✓${NC} DNS VNet link not present (skipping)"
fi

# INC-4523/4524: Students modify NSG rules and associations via az CLI.
# When Terraform destroys VMs and NSG-NIC associations concurrently, Azure
# blocks the NIC update because the VM is already marked for deletion.
# Removing NSG-NIC associations up-front prevents this race condition.
for ROLE in bastion web api database; do
    NIC_NAME="nic-${ROLE}-${DEPLOYMENT_ID}"
    if az network nic show --resource-group "$RESOURCE_GROUP" --name "$NIC_NAME" &>/dev/null; then
        echo "  Removing NSG from NIC '$NIC_NAME'..."
        az network nic update \
            --resource-group "$RESOURCE_GROUP" \
            --name "$NIC_NAME" \
            --network-security-group "" &>/dev/null
        echo -e "  ${GREEN}✓${NC} NSG removed from $NIC_NAME"
    fi
done

echo ""

# Destroy
echo "Destroying infrastructure..."
terraform destroy -auto-approve

# Clean up SSH key
if [ -f ~/.ssh/netlab-key ]; then
    rm -f ~/.ssh/netlab-key
    echo "Removed SSH key from ~/.ssh/netlab-key"
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   CLEANUP COMPLETE${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "All resources have been destroyed."
echo "Thanks for using the L2C Networking Lab!"
echo ""
