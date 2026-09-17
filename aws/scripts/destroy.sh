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

# Identify the deployment. After a partial destroy the outputs are gone, so fall
# back to the state file, and only accept well-formed values.
state_attribute() { # resource type, attribute
    jq -r --arg type "$1" --arg attr "$2" \
        '.resources[]? | select(.type == $type) | .instances[]?.attributes[$attr] // empty' \
        terraform.tfstate 2>/dev/null | head -n 1
}
VPC_ID=$( (terraform output -raw vpc_id 2>/dev/null || true) | grep -Eo '^vpc-[0-9a-f]+$' || true)
if [ -z "$VPC_ID" ]; then
    VPC_ID=$(state_attribute aws_vpc id | grep -Eo '^vpc-[0-9a-f]+$' || true)
fi
REGION=$( (terraform output -raw region 2>/dev/null || true) | grep -Eo '^[a-z]{2}(-[a-z]+)+-[0-9]$' || true)
if [ -z "$REGION" ]; then
    REGION=$(state_attribute aws_vpc arn | sed -n 's/^arn:aws:ec2:\([a-z0-9-]*\):.*/\1/p')
fi
if [ -z "$REGION" ]; then
    REGION=$(aws configure get region 2>/dev/null || true)
fi
AWS_ARGS=()
if [ -n "$REGION" ]; then
    AWS_ARGS=(--region "$REGION")
fi

echo "VPC to destroy: ${VPC_ID:-unknown} (region: ${REGION:-default})"
echo ""
read -p "Are you sure you want to destroy all resources? (yes/N) " -r
echo ""

if [[ ! $REPLY == "yes" ]]; then
    echo "Aborted. Type 'yes' (not just 'y') to confirm destruction."
    exit 0
fi

# Destroy
echo "Cleaning up dependencies (Route53 records, SG references)..."

# Use this deployment's zone, not a name search that could select another lab.
ZONE_ID=$( (terraform output -raw dns_zone_id 2>/dev/null || true) | grep -Eo '^(/hostedzone/)?Z[0-9A-Z]+$' || true)
if [ -z "$ZONE_ID" ]; then
    ZONE_ID=$(state_attribute aws_route53_zone zone_id | grep -Eo '^Z[0-9A-Z]+$' || true)
fi
ZONE_ID="${ZONE_ID#/hostedzone/}"
if [ -n "$ZONE_ID" ]; then
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

# Security groups Terraform manages (by resource, not by reference: managed
# groups can reference unmanaged ones, so a plain text search is not enough).
managed_security_groups() {
    jq -r '.resources[]? | select(.type == "aws_security_group") | .instances[]?.attributes.id // empty' \
        terraform.tfstate 2>/dev/null
}

unmanaged_security_groups() {
    local SG MANAGED
    [ -n "$VPC_ID" ] || return 0
    MANAGED=" $(managed_security_groups | tr '\n' ' ') "
    for SG in $(aws "${AWS_ARGS[@]}" ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "SecurityGroups[?GroupName!='default'].GroupId" --output text 2>/dev/null | tr -d '\r'); do
        case "$MANAGED" in
            *" $SG "*) ;;
            *) echo "$SG" ;;
        esac
    done
}

# Remove rules from security groups in the lab VPC that Terraform does not
# manage (created during INC-4523/INC-4524 repairs), so cross-references do not
# block deletion. Terraform revokes rules on its own groups.
sweep_extra_security_groups() {
    local SG PERMISSIONS
    for SG in $(unmanaged_security_groups); do
        echo "Removing rules from unmanaged security group $SG"
        PERMISSIONS=$(aws "${AWS_ARGS[@]}" ec2 describe-security-groups --group-ids "$SG" \
            --query 'SecurityGroups[0].IpPermissions' --output json 2>/dev/null || echo "[]")
        if [ "$PERMISSIONS" != "[]" ] && [ -n "$PERMISSIONS" ]; then
            aws "${AWS_ARGS[@]}" ec2 revoke-security-group-ingress --group-id "$SG" \
                --ip-permissions "$PERMISSIONS" >/dev/null 2>&1 || true
        fi
        PERMISSIONS=$(aws "${AWS_ARGS[@]}" ec2 describe-security-groups --group-ids "$SG" \
            --query 'SecurityGroups[0].IpPermissionsEgress' --output json 2>/dev/null || echo "[]")
        if [ "$PERMISSIONS" != "[]" ] && [ -n "$PERMISSIONS" ]; then
            aws "${AWS_ARGS[@]}" ec2 revoke-security-group-egress --group-id "$SG" \
                --ip-permissions "$PERMISSIONS" >/dev/null 2>&1 || true
        fi
    done
}

delete_extra_security_groups() {
    local SG
    for SG in $(unmanaged_security_groups); do
        echo "Deleting leftover security group $SG"
        aws "${AWS_ARGS[@]}" ec2 delete-security-group --group-id "$SG" >/dev/null 2>&1 || true
    done
}

sweep_extra_security_groups

# Remove the instances first so that security groups created outside Terraform
# are no longer attached; otherwise an unmanaged group blocks VPC deletion and
# Terraform retries for its full 20-minute timeout before failing.
echo "Destroying instances..."
terraform destroy -target=module.compute -auto-approve
delete_extra_security_groups

echo "Destroying remaining infrastructure..."
set +e
terraform destroy -auto-approve
DESTROY_EXIT=$?
set -e

if [ $DESTROY_EXIT -ne 0 ]; then
    echo ""
    echo "Terraform destroy failed; removing leftover security groups and retrying once..."
    sweep_extra_security_groups
    delete_extra_security_groups
    terraform destroy -auto-approve
fi

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
echo "All Terraform-managed resources have been destroyed."
echo "If you created extra resources with the AWS CLI (Elastic IPs, routes,"
echo "security groups, VPCs), confirm they are gone in the AWS console."
echo "Thanks for using the L2C Networking Lab!"
echo ""
