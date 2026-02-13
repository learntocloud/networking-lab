#!/bin/bash
# =============================================================================
# NETWORKING LAB - SETUP SCRIPT (GCP)
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
echo -e "${BLUE}   NETWORKING LAB - SETUP (GCP)${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------------

echo "Checking prerequisites..."

# Check gcloud CLI
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Error: gcloud CLI not found.${NC}"
    echo "Install it from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} gcloud CLI found"

# Check gcloud auth
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo -e "${YELLOW}Not logged in to GCP. Running 'gcloud auth login'...${NC}"
    gcloud auth login
fi
ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1)
echo -e "  ${GREEN}✓${NC} Logged in to GCP: $ACCOUNT"

# Check project
PROJECT_ID=${TF_VAR_project_id:-$(gcloud config get-value project 2>/dev/null || echo "")}
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
    echo -e "${YELLOW}No GCP project set.${NC}"
    echo -n "Enter your GCP project ID: "
    read PROJECT_ID
    if [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}Error: Project ID is required.${NC}"
        exit 1
    fi
    gcloud config set project "$PROJECT_ID" >/dev/null
fi
echo -e "  ${GREEN}✓${NC} Project: $PROJECT_ID"

# Check Terraform
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform not found.${NC}"
    echo "Install it from: https://www.terraform.io/downloads"
    exit 1
fi

# Check jq (required for parsing Terraform version)
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq not found.${NC}"
    echo "Install it from: https://jqlang.org/download/"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} jq found"

TF_VERSION=$(terraform version -json | jq -r '.terraform_version')
echo -e "  ${GREEN}✓${NC} Terraform found: v$TF_VERSION"

# Enable required APIs
echo ""
echo "Enabling required APIs..."
gcloud services enable compute.googleapis.com dns.googleapis.com --project "$PROJECT_ID" >/dev/null

echo -e "  ${GREEN}✓${NC} APIs enabled"

# -----------------------------------------------------------------------------
# Deploy infrastructure
# -----------------------------------------------------------------------------

echo ""
echo "Deploying infrastructure..."
echo -e "${YELLOW}This will create GCP resources that incur costs (~\$0.50-1.00/session).${NC}"
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
TF_VAR_project_id="$PROJECT_ID" terraform plan -out=tfplan

# Apply
echo ""
echo "Applying infrastructure..."
TF_VAR_project_id="$PROJECT_ID" terraform apply tfplan

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
