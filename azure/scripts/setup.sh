#!/bin/bash
# =============================================================================
# NETWORKING LAB - SETUP SCRIPT
# Deploys the intentionally broken infrastructure for learning
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

source "${SCRIPT_DIR}/common.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   NETWORKING LAB - SETUP${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------------

echo "Checking prerequisites..."
require_commands jq ssh python3 curl

# Check Azure CLI
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI not found.${NC}"
    echo "Install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Azure CLI found"

# Check Azure login
if ! az account show &> /dev/null; then
    echo -e "${YELLOW}Not logged in to Azure. Running 'az login'...${NC}"
    az login
fi
ACCOUNT=$(az account show --query name -o tsv)
echo -e "  ${GREEN}✓${NC} Logged in to Azure: $ACCOUNT"

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
echo -e "${YELLOW}This will create Azure resources that incur costs (~\$0.50-1.00/session).${NC}"
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
report_setup_failure() {
    local STATUS=$?
    if [ "$STATUS" -ne 0 ]; then
        echo "Error: Lab preparation failed; the lab is NOT ready." >&2
        echo "Resources may remain deployed. Inspect the error, then retry setup or run $SCRIPT_DIR/destroy.sh to avoid charges." >&2
    fi
}
trap report_setup_failure EXIT
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
mkdir -p "$HOME/.ssh"
(umask 077; terraform output -raw ssh_private_key > "$HOME/.ssh/netlab-key")
chmod 600 ~/.ssh/netlab-key
echo -e "  ${GREEN}✓${NC} SSH key saved to ~/.ssh/netlab-key"

load_lab_outputs
PRIVATE_SUBNET_ID=$(get_terraform_output private_subnet_id)

wait_for_vm() {
    local NAME="$1" IP="$2" ATTEMPT SSH_ERROR
    echo "Waiting for $NAME SSH and cloud-init..."
    for ATTEMPT in {1..30}; do
        if SSH_ERROR=$(run_on_vm "$IP" true 10 2>&1); then
            break
        fi
        if [ "$ATTEMPT" -eq 30 ]; then
            printf 'Error: %s SSH did not become ready: %s\n' "$NAME" "$SSH_ERROR" >&2
            return 1
        fi
        sleep 5
    done
    run_on_vm "$IP" '
        cloud-init status --wait --long
        STATUS=$?
        if [ "$STATUS" -eq 2 ]; then
            echo "Warning: cloud-init reported recoverable errors; checking tools and service health."
        elif [ "$STATUS" -ne 0 ]; then
            exit "$STATUS"
        fi
        test -f /var/lib/cloud/instance/boot-finished
    ' 600
    check_vm_tools "$IP"
}

echo ""
echo "Checking VM initialization before preparing the incidents..."
wait_for_vm bastion "$BASTION_IP"
wait_for_vm web "$WEB_IP"
wait_for_vm API "$API_IP"
wait_for_vm database "$DB_IP"

run_on_vm "$WEB_IP" 'curl -fsS --max-time 10 http://localhost/health && curl -kfsS --max-time 10 https://localhost/health'
echo "Checking local services and both blocked application paths..."
if check_application_paths; then
    STATUS=0
else
    STATUS=$?
fi
if [ "$STATUS" -ne 1 ] || [ "$WEB_API_STATE" != unresolved ] || [ "$API_DB_STATE" != unresolved ]; then
    echo "Error: The application-port incident is not in its expected initial state. $PORTS_DETAIL" >&2
    exit 1
fi
echo "$PORTS_DETAIL"

if ! check_api_egress; then
    echo "Error: Healthy API egress was not established: $EGRESS_DETAIL" >&2
    exit 1
fi
echo "$EGRESS_DETAIL"

echo "Preparing the outbound connectivity incident..."
az network vnet subnet update --ids "$PRIVATE_SUBNET_ID" --remove natGateway -o none
SUBNET=$(az network vnet subnet show --ids "$PRIVATE_SUBNET_ID" -o json)
if ! jq -e '.defaultOutboundAccess == false and .natGateway == null' <<< "$SUBNET" >/dev/null; then
    echo "Error: The private subnet did not reach the expected initial configuration." >&2
    exit 1
fi

FAULT_READY=false
for ATTEMPT in {1..6}; do
    if probe_api_https; then
        sleep 5
    else
        STATUS=$?
        if [ "$STATUS" -eq 1 ]; then
            FAULT_READY=true
            break
        fi
        echo "Error: Could not confirm the initial fault: $EGRESS_DETAIL" >&2
        exit 1
    fi
done
if [ "$FAULT_READY" != true ]; then
    echo "Error: API external HTTPS still works after preparing the incident." >&2
    exit 1
fi
run_on_vm "$API_IP" 'getent ahostsv4 example.com >/dev/null && curl -fsS --max-time 10 http://localhost:8080/health | jq -e ".status == \"healthy\""'

echo "Checking public DNS from every VM..."
for IP in "$BASTION_IP" "$WEB_IP" "$API_IP" "$DB_IP"; do
    if ! run_on_vm "$IP" '
        ANSWER=$(dig +time=3 +tries=2 +short @168.63.129.16 google.com A) &&
            printf "%s\n" "$ANSWER" | grep -Eq "^[0-9]+(\.[0-9]+){3}$" &&
            timeout 10 getent ahostsv4 google.com >/dev/null
    '; then
        echo "Error: Public DNS is not working on $IP; the DNS incident baseline is not ready." >&2
        exit 1
    fi
done

# Show deployment region
LOCATION=$(get_terraform_output location)
echo -e "  ${GREEN}✓${NC} Region: $LOCATION"

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   READY TO START!${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "Your broken infrastructure is deployed."
echo "Work through the tasks in README.md to fix it."
echo ""
terraform output -raw connection_instructions
echo ""
echo "Validate your progress anytime with:"
echo "  $SCRIPT_DIR/validate.sh"
echo ""
echo "When done, clean up with:"
echo "  $SCRIPT_DIR/destroy.sh"
echo ""
