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

echo "Resource group to destroy: $RESOURCE_GROUP"
echo ""
read -p "Are you sure you want to destroy all resources? (yes/N) " -r
echo ""

if [[ ! $REPLY == "yes" ]]; then
    echo "Aborted. Type 'yes' (not just 'y') to confirm destruction."
    exit 0
fi

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
echo "Thanks for using Networking Lab!"
echo ""
