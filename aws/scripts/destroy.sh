#!/bin/bash
# =============================================================================
# NETWORKING LAB - AWS DESTROY SCRIPT
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
echo -e "${RED}   NETWORKING LAB - DESTROY (AWS)${NC}"
echo -e "${RED}============================================${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will destroy ALL lab resources!${NC}"
echo ""

# Check if state exists
if [ ! -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
    echo "No terraform state found. Nothing to destroy."
    exit 0
fi

cd "$TERRAFORM_DIR"

# Get VPC for confirmation
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "unknown")

echo "VPC to destroy: $VPC_ID"
echo ""
read -p "Are you sure you want to destroy all resources? (yes/N) " -r
echo ""

if [[ ! $REPLY == "yes" ]]; then
    echo "Aborted. Type 'yes' (not just 'y') to confirm destruction."
    exit 0
fi

# Destroy
echo "Cleaning up dependencies (Route53 records, SG references)..."

# Remove non-required Route53 records from the private zone (if present)
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
    --dns-name "internal.local" \
    --query "HostedZones[?Config.PrivateZone==\`true\`].Id" --output text 2>/dev/null | head -n 1)
ZONE_ID="${ZONE_ID#/hostedzone/}"
if [ -n "$ZONE_ID" ] && [ "$ZONE_ID" != "None" ]; then
    for _ in {1..5}; do
        RECORDS_JSON=$(aws route53 list-resource-record-sets \
            --hosted-zone-id "$ZONE_ID" \
            --query "ResourceRecordSets[?Type!='NS' && Type!='SOA']" --output json 2>/dev/null)

        if [ -z "$RECORDS_JSON" ] || [ "$RECORDS_JSON" = "[]" ]; then
            break
        fi

        CHANGE_BATCH=$(printf '{"Changes":%s}' "$(echo "$RECORDS_JSON" | jq '[.[] | {Action:"DELETE", ResourceRecordSet:.}]')")
        aws route53 change-resource-record-sets \
            --hosted-zone-id "$ZONE_ID" \
            --change-batch "$CHANGE_BATCH" >/dev/null 2>&1 || true
        sleep 5
    done
fi


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
