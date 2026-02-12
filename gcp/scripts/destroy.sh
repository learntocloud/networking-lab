#!/bin/bash
# =============================================================================
# NETWORKING LAB - DESTROY SCRIPT (GCP)
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
echo -e "${RED}   NETWORKING LAB - DESTROY (GCP)${NC}"
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
PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || echo "")
DEPLOYMENT_ID=$(terraform output -raw deployment_id 2>/dev/null || echo "")

if [ -z "$PROJECT_ID" ]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
fi

echo "Project to destroy: ${PROJECT_ID:-unknown}"
echo ""
read -p "Are you sure you want to destroy all resources? (yes/N) " -r
echo ""

if [[ ! $REPLY == "yes" ]]; then
    echo "Aborted. Type 'yes' (not just 'y') to confirm destruction."
    exit 0
fi

# Remove ad-hoc firewall rules created during lab fixes
if [ -n "$PROJECT_ID" ] && [ -n "$DEPLOYMENT_ID" ] && command -v gcloud >/dev/null 2>&1; then
    EXTRA_RULES=("allow-web-to-api-8080-${DEPLOYMENT_ID}")
    for RULE in "${EXTRA_RULES[@]}"; do
        if gcloud compute firewall-rules describe "$RULE" --project "$PROJECT_ID" >/dev/null 2>&1; then
            echo "Deleting firewall rule: $RULE"
            gcloud compute firewall-rules delete "$RULE" --project "$PROJECT_ID" -q >/dev/null 2>&1 || true
        fi
    done
fi

# Remove Cloud DNS records so the managed zone can be deleted
if [ -n "$PROJECT_ID" ] && [ -n "$DEPLOYMENT_ID" ] && command -v gcloud >/dev/null 2>&1; then
    ZONE_NAME="internal-local-${DEPLOYMENT_ID}"
    if gcloud dns managed-zones describe "$ZONE_NAME" --project "$PROJECT_ID" >/dev/null 2>&1; then
        echo "Cleaning up DNS records in zone: $ZONE_NAME"

        get_record() {
            local NAME="$1"
            gcloud dns record-sets list \
                --zone "$ZONE_NAME" \
                --project "$PROJECT_ID" \
                --name "$NAME" \
                --type A \
                --format="value(ttl,rrdatas)"
        }

        WEB_REC=$(get_record "web.internal.local.")
        API_REC=$(get_record "api.internal.local.")
        DB_REC=$(get_record "db.internal.local.")

        gcloud dns record-sets transaction start --zone "$ZONE_NAME" --project "$PROJECT_ID" >/dev/null 2>&1 || true

        REMOVE_COUNT=0
        if [ -n "$WEB_REC" ]; then
            read -r WEB_TTL WEB_IP <<< "$WEB_REC"
            gcloud dns record-sets transaction remove "$WEB_IP" \
                --name "web.internal.local." --ttl "$WEB_TTL" --type A \
                --zone "$ZONE_NAME" --project "$PROJECT_ID" >/dev/null 2>&1 && REMOVE_COUNT=$((REMOVE_COUNT + 1))
        fi

        if [ -n "$API_REC" ]; then
            read -r API_TTL API_IP <<< "$API_REC"
            gcloud dns record-sets transaction remove "$API_IP" \
                --name "api.internal.local." --ttl "$API_TTL" --type A \
                --zone "$ZONE_NAME" --project "$PROJECT_ID" >/dev/null 2>&1 && REMOVE_COUNT=$((REMOVE_COUNT + 1))
        fi

        if [ -n "$DB_REC" ]; then
            read -r DB_TTL DB_IP <<< "$DB_REC"
            gcloud dns record-sets transaction remove "$DB_IP" \
                --name "db.internal.local." --ttl "$DB_TTL" --type A \
                --zone "$ZONE_NAME" --project "$PROJECT_ID" >/dev/null 2>&1 && REMOVE_COUNT=$((REMOVE_COUNT + 1))
        fi

        if [ "$REMOVE_COUNT" -gt 0 ]; then
            gcloud dns record-sets transaction execute --zone "$ZONE_NAME" --project "$PROJECT_ID" >/dev/null 2>&1 || true
        else
            gcloud dns record-sets transaction abort --zone "$ZONE_NAME" --project "$PROJECT_ID" >/dev/null 2>&1 || true
        fi
    fi
fi

# Destroy
if [ -n "$PROJECT_ID" ]; then
    TF_VAR_project_id="$PROJECT_ID" terraform destroy -auto-approve
else
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
echo "All resources have been destroyed."
echo "Thanks for using Networking Lab!"
echo ""
