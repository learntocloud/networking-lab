#!/bin/bash
# =============================================================================
# NETWORKING LAB - AWS SETUP SCRIPT
# Deploys the intentionally broken infrastructure for learning
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   NETWORKING LAB - SETUP (AWS)${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------------

echo "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI not found.${NC}"
    echo "Install it from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} AWS CLI found"

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured.${NC}"
    echo "Run: aws configure"
    exit 1
fi
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo -e "  ${GREEN}✓${NC} AWS credentials OK (Account: $ACCOUNT)"

# Check Terraform
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform not found.${NC}"
    echo "Install it from: https://www.terraform.io/downloads"
    exit 1
fi
TF_VERSION=$(terraform version -json | jq -r '.terraform_version')
echo -e "  ${GREEN}✓${NC} Terraform found: v$TF_VERSION"

# -----------------------------------------------------------------------------
# Deploy infrastructure
# -----------------------------------------------------------------------------

echo ""
echo "Deploying infrastructure..."
echo -e "${YELLOW}This will create AWS resources that incur costs (~\$0.50-1.00/session).${NC}"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

cd "$TERRAFORM_DIR"

# Initialize Terraform
echo ""
echo "Initializing Terraform..."
terraform init

# Plan
echo ""
echo "Planning deployment..."
terraform plan -out=tfplan

# Apply
echo ""
echo "Applying infrastructure..."
terraform apply tfplan

# Clean up plan file
rm -f tfplan

# -----------------------------------------------------------------------------
# Post-deployment info
# -----------------------------------------------------------------------------

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   DEPLOYMENT COMPLETE!${NC}"
echo -e "${GREEN}============================================${NC}"

# Save SSH key
echo ""
echo "Saving SSH key..."
terraform output -raw ssh_private_key > ~/.ssh/netlab-key 2>/dev/null
chmod 600 ~/.ssh/netlab-key
echo -e "  ${GREEN}✓${NC} SSH key saved to ~/.ssh/netlab-key"

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   READY TO START!${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "Your broken infrastructure is deployed."
echo "Work through the tasks in README.md to fix it."
echo ""
echo "Validate your progress anytime with:"
echo "  ./scripts/validate.sh"
echo ""
echo "When done, clean up with:"
echo "  ./scripts/destroy.sh"
echo ""
