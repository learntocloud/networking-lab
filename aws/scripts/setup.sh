#!/bin/bash
# =============================================================================
# NETWORKING LAB - AWS SETUP SCRIPT
# Deploys the infrastructure, waits for a healthy baseline, then prepares the
# intentional incidents.
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
echo -e "${BLUE}   NETWORKING LAB - SETUP (AWS)${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------------

echo "Checking prerequisites..."
require_commands jq ssh python3 curl

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI not found.${NC}"
    echo "Install it from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} AWS CLI found"

# Check AWS credentials
if ! IDENTITY=$(aws sts get-caller-identity --output json 2>/dev/null); then
    echo -e "${RED}Error: AWS credentials not configured.${NC}"
    echo "Run: aws configure"
    exit 1
fi
ACCOUNT=$(jq -r '.Account' <<< "$IDENTITY")
IDENTITY_ARN=$(jq -r '.Arn' <<< "$IDENTITY")
echo -e "  ${GREEN}✓${NC} AWS credentials OK (Account: $ACCOUNT, $IDENTITY_ARN)"

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
echo -e "${YELLOW}This will create AWS resources that incur costs (~\$0.50-1.00/session):${NC}"
echo -e "${YELLOW}four t3.micro instances, a NAT gateway, and three public IPv4 addresses.${NC}"
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
        echo "Resources may remain. Retry setup or run $SCRIPT_DIR/destroy.sh to avoid charges." >&2
    fi
}
trap report_setup_failure EXIT
terraform apply tfplan

# Clean up plan file
rm -f tfplan

# -----------------------------------------------------------------------------
# Post-deployment checks and incident preparation
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

# Route 53 negative caching defaults to the SOA minimum TTL (15 minutes), which
# would hide repaired INC-4522 records for a long time. Keep the SOA content and
# lower only the TTLs.
echo "Shortening the private zone's negative-caching TTL..."
SOA=$(aws route53 list-resource-record-sets --hosted-zone-id "$DNS_ZONE_ID" --output json \
    --query "ResourceRecordSets[?Type=='SOA'] | [0]")
SOA_NAME=$(jq -r '.Name' <<< "$SOA")
SOA_VALUE=$(jq -r '.ResourceRecords[0].Value' <<< "$SOA" | awk '{ $7 = 60; print }')
aws route53 change-resource-record-sets --hosted-zone-id "$DNS_ZONE_ID" --output text \
    --query 'ChangeInfo.Status' --change-batch "$(jq -cn --arg name "$SOA_NAME" --arg value "$SOA_VALUE" \
    '{Changes: [{Action: "UPSERT", ResourceRecordSet: {Name: $name, Type: "SOA", TTL: 60, ResourceRecords: [{Value: $value}]}}]}')"

wait_for_vm() {
    local NAME="$1" IP="$2" ATTEMPT SSH_ERROR
    echo "Waiting for $NAME SSH and cloud-init..."
    for ATTEMPT in {1..36}; do
        if SSH_ERROR=$(run_on_vm "$IP" true 10 2>&1); then
            break
        fi
        if [ "$ATTEMPT" -eq 36 ]; then
            printf 'Error: %s SSH did not become ready: %s\n' "$NAME" "$SSH_ERROR" >&2
            return 1
        fi
        sleep 5
    done
    run_on_vm "$IP" '
        cloud-init status --wait >/dev/null
        STATUS=$?
        if [ "$STATUS" -eq 2 ]; then
            echo "Warning: cloud-init reported recoverable errors; checking tools and services."
        elif [ "$STATUS" -ne 0 ]; then
            echo "Error: cloud-init failed (status $STATUS). Inspect sudo cat /var/log/cloud-init-output.log" >&2
            exit "$STATUS"
        fi
        test -f /var/lib/netlab-startup-complete || {
            echo "Error: The lab initialization script did not finish. Inspect sudo cat /var/log/cloud-init-output.log" >&2
            exit 1
        }
    ' 900
    check_vm_tools "$IP"
}

echo ""
echo "Checking instance initialization before preparing the incidents..."
wait_for_vm bastion "$BASTION_IP"
wait_for_vm web "$WEB_IP"
wait_for_vm API "$API_IP"
wait_for_vm database "$DB_IP"

run_on_vm "$WEB_IP" 'curl -fsS --max-time 10 http://localhost/health && curl -kfsS --max-time 10 https://localhost/health'
echo "Checking local services and both blocked application paths..."
STATUS=0
check_application_paths || STATUS=$?
if [ "$STATUS" -ne 1 ] || [ "$WEB_API_STATE" != unresolved ] || [ "$API_DB_STATE" != unresolved ]; then
    echo "Error: Expected both application paths blocked with healthy local services. $PORTS_DETAIL" >&2
    exit 1
fi
echo "$PORTS_DETAIL"

if ! check_api_egress; then
    echo "Error: Healthy bootstrap egress was not established. $EGRESS_DETAIL" >&2
    exit 1
fi
echo "$EGRESS_DETAIL"

echo "Preparing the outbound connectivity incident..."
if aws_json ec2 describe-route-tables --route-table-ids "$PRIVATE_ROUTE_TABLE_ID" \
    --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`]' | jq -e 'length > 0' >/dev/null; then
    aws --region "$REGION" ec2 delete-route --route-table-id "$PRIVATE_ROUTE_TABLE_ID" \
        --destination-cidr-block 0.0.0.0/0
fi
FAULT_READY=false
for ATTEMPT in {1..6}; do
    if probe_api_https; then
        sleep 5
    else
        STATUS=$?
        if [ "$STATUS" -eq 1 ]; then FAULT_READY=true; break; fi
        echo "Error: Could not confirm the initial egress fault. $EGRESS_DETAIL" >&2
        exit 1
    fi
done
if [ "$FAULT_READY" != true ]; then
    echo "Error: API external HTTPS still works after preparing the NAT incident." >&2
    exit 1
fi
if ! probe_api_health "$API_IP" 127.0.0.1; then
    echo "Error: API health failed after preparing the NAT incident. $SERVICE_DETAIL" >&2
    exit 1
fi

echo "Checking public DNS from every instance..."
for IP in "$BASTION_IP" "$WEB_IP" "$API_IP" "$DB_IP"; do
    if ! run_on_vm "$IP" '
        ANSWER=$(dig +time=3 +tries=2 +short @169.254.169.253 google.com A) &&
        printf "%s\n" "$ANSWER" | grep -Eq "^[0-9]+(\.[0-9]+){3}$" &&
        timeout 10 getent ahostsv4 google.com >/dev/null
    '; then
        echo "Error: Public DNS baseline failed on $IP." >&2
        exit 1
    fi
done

echo -e "  ${GREEN}✓${NC} Region: $REGION"

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   READY TO START!${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "Your broken infrastructure is deployed."
echo "Work through the tasks in README.md to fix it."
terraform output -raw connection_instructions
echo ""
echo "Validate your progress anytime with:"
echo "  $SCRIPT_DIR/validate.sh"
echo ""
echo "When done, clean up with:"
echo "  $SCRIPT_DIR/destroy.sh"
echo ""
