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
RAW_PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || true)
RAW_DEPLOYMENT_ID=$(terraform output -raw deployment_id 2>/dev/null || true)
PROJECT_ID=$(printf '%s\n' "$RAW_PROJECT_ID" | awk '/^[a-z][a-z0-9-]{4,61}[a-z0-9]$/ { print; exit }')
DEPLOYMENT_ID=$(printf '%s\n' "$RAW_DEPLOYMENT_ID" | awk '/^[0-9a-f]{8}$/ { print; exit }')

if [ -z "$PROJECT_ID" ]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
fi
if [ -z "$PROJECT_ID" ] && [ -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
    if command -v jq >/dev/null 2>&1; then
        PROJECT_ID=$(jq -r '.resources[] | select(.type=="google_dns_managed_zone") | .instances[].attributes.id' "${TERRAFORM_DIR}/terraform.tfstate" 2>/dev/null | sed -n 's#projects/\([^/]*\)/managedZones/.*#\1#p' | head -n1)
    else
        PROJECT_ID=$(awk '
            /"type": "google_dns_managed_zone"/ { in_zone=1; next }
            in_zone && /"id": "projects\/[^"]+\/managedZones\/[^"]+"/ {
                line=$0
                sub(/.*"id": "projects\//, "", line)
                sub(/\/managedZones\/.*/, "", line)
                print line
                in_zone=0
            }
        ' "${TERRAFORM_DIR}/terraform.tfstate" | head -n1)
    fi
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
if [ -n "$PROJECT_ID" ] && command -v gcloud >/dev/null 2>&1; then
    ZONE_NAMES=()

    # Prefer zones referenced by Terraform state, because outputs may be missing in partial state.
    if [ -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
        if command -v jq >/dev/null 2>&1; then
            while IFS= read -r ZONE; do
                [ -n "$ZONE" ] && ZONE_NAMES+=("$ZONE")
            done < <(jq -r '.resources[] | select(.type=="google_dns_managed_zone") | .instances[].attributes.name' "${TERRAFORM_DIR}/terraform.tfstate" 2>/dev/null || true)
        else
            while IFS= read -r ZONE; do
                [ -n "$ZONE" ] && ZONE_NAMES+=("$ZONE")
            done < <(awk '
                /"type": "google_dns_managed_zone"/ { in_zone=1; next }
                in_zone && /"id": "projects\/[^"]+\/managedZones\/[^"]+"/ {
                    line=$0
                    sub(/.*managedZones\//, "", line)
                    sub(/".*/, "", line)
                    print line
                    in_zone=0
                }
            ' "${TERRAFORM_DIR}/terraform.tfstate")
        fi
    fi

    # Fallback to deployment-derived zone name if state parsing found nothing.
    if [ "${#ZONE_NAMES[@]}" -eq 0 ] && [ -n "$DEPLOYMENT_ID" ]; then
        ZONE_NAMES+=("internal-local-${DEPLOYMENT_ID}")
    fi

    for ZONE_NAME in "${ZONE_NAMES[@]}"; do
        if ! gcloud dns managed-zones describe "$ZONE_NAME" --project "$PROJECT_ID" >/dev/null 2>&1; then
            echo "Skipping DNS zone cleanup for ${ZONE_NAME}: zone not accessible in project ${PROJECT_ID}."
            continue
        fi

        echo "Cleaning up DNS records in zone: $ZONE_NAME"
        DNS_NAME=$(gcloud dns managed-zones describe "$ZONE_NAME" --project "$PROJECT_ID" --format="value(dnsName)" 2>/dev/null || true)
        if [ -z "$DNS_NAME" ]; then
            echo "Skipping DNS zone cleanup for ${ZONE_NAME}: unable to read zone metadata."
            continue
        fi

        while read -r RECORD_NAME RECORD_TYPE; do
            [ -z "$RECORD_NAME" ] && continue
            # Keep required apex records; delete everything else.
            if [ "$RECORD_NAME" = "$DNS_NAME" ] && { [ "$RECORD_TYPE" = "NS" ] || [ "$RECORD_TYPE" = "SOA" ]; }; then
                continue
            fi

            echo "Deleting DNS record-set: ${RECORD_NAME} (${RECORD_TYPE})"
            gcloud dns record-sets delete "$RECORD_NAME" \
                --type "$RECORD_TYPE" \
                --zone "$ZONE_NAME" \
                --project "$PROJECT_ID" \
                -q >/dev/null 2>&1 || echo "Warning: failed to delete ${RECORD_NAME} (${RECORD_TYPE})"
        done < <(gcloud dns record-sets list \
            --zone "$ZONE_NAME" \
            --project "$PROJECT_ID" \
            --format="value(name,type)" 2>/dev/null || true)

        REMAINING=$(gcloud dns record-sets list \
            --zone "$ZONE_NAME" \
            --project "$PROJECT_ID" \
            --format="value(name,type)" 2>/dev/null | awk -v dns_name="$DNS_NAME" '$0 != dns_name " NS" && $0 != dns_name " SOA"' || true)
        if [ -n "$REMAINING" ]; then
            echo "Warning: zone ${ZONE_NAME} still has non-default records:"
            echo "$REMAINING"
        fi
    done
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
