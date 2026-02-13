#!/bin/bash
# =============================================================================
# NETWORKING LAB - AWS VALIDATION SCRIPT
# Validates incident resolution by testing actual connectivity
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Incident tracking 
INC_4521="pending"
INC_4522="pending"
INC_4523="pending"
INC_4524="pending"

# Master secret for token generation (matches verification service)
MASTER_SECRET="L2C_CTF_MASTER_2024"

# SSH options for non-interactive use (-n prevents stdin consumption)
SSH_OPTS="-n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -q"

# =============================================================================
# Helper Functions
# =============================================================================

get_terraform_output() {
    cd "$TERRAFORM_DIR"
    terraform output -raw "$1" 2>/dev/null || echo ""
}

# Run a command on a VM via SSH through bastion
run_on_vm() {
    local TARGET_IP="$1"
    local CMD="$2"

    ssh $SSH_OPTS -i "$SSH_KEY" "$ADMIN_USERNAME@$BASTION_IP" \
        "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $ADMIN_USERNAME@$TARGET_IP '$CMD' 2>/dev/null" 2>/dev/null | tr -d '\n\r'
}

# =============================================================================
# Pre-flight checks (silent)
# =============================================================================

preflight_check() {
    # Check if terraform state exists
    if [ ! -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
        echo -e "${RED}Error: No terraform state found. Run './setup.sh' first.${NC}"
        exit 1
    fi

    # Check for SSH key
    if [ ! -f "$HOME/.ssh/netlab-key" ]; then
        echo -e "${RED}Error: SSH key not found at ~/.ssh/netlab-key${NC}"
        echo "Run: cd ../terraform && terraform output -raw ssh_private_key > ~/.ssh/netlab-key && chmod 600 ~/.ssh/netlab-key"
        exit 1
    fi

    # Get outputs from terraform
    DEPLOYMENT_ID=$(get_terraform_output "deployment_id")
    BASTION_IP=$(get_terraform_output "bastion_public_ip")
    WEB_IP=$(get_terraform_output "web_server_private_ip")
    API_IP=$(get_terraform_output "api_server_private_ip")
    DB_IP=$(get_terraform_output "database_server_private_ip")
    SSH_KEY="$HOME/.ssh/netlab-key"
    ADMIN_USERNAME=$(get_terraform_output "admin_username")

    BASTION_SG_ID=$(get_terraform_output "bastion_sg_id")
    WEB_SG_ID=$(get_terraform_output "web_sg_id")
    API_SG_ID=$(get_terraform_output "api_sg_id")
    DB_SG_ID=$(get_terraform_output "db_sg_id")

    if [ -z "$BASTION_IP" ] || [ -z "$ADMIN_USERNAME" ]; then
        echo -e "${RED}Error: Could not get terraform outputs. Is the infrastructure deployed?${NC}"
        exit 1
    fi

    # Test bastion connectivity
    if ! ssh $SSH_OPTS -i "$SSH_KEY" "$ADMIN_USERNAME@$BASTION_IP" "echo ok" >/dev/null 2>&1; then
        echo -e "${RED}Error: Cannot reach bastion host${NC}"
        exit 1
    fi

    export DEPLOYMENT_ID BASTION_IP WEB_IP API_IP DB_IP SSH_KEY ADMIN_USERNAME
    export BASTION_SG_ID WEB_SG_ID API_SG_ID DB_SG_ID
}

# =============================================================================
# Incident Validation
# =============================================================================

validate_inc_4521() {
    local RESULT=$(run_on_vm "$API_IP" "curl -s --max-time 10 -o /dev/null -w '%{http_code}' https://example.com 2>/dev/null || echo 'failed'")
    if [ "$RESULT" == "200" ]; then
        INC_4521="resolved"
    else
        INC_4521="unresolved"
    fi
}

validate_inc_4522() {
    local WEB_RESOLVES=$(run_on_vm "$WEB_IP" "nslookup web.internal.local 169.254.169.253 2>/dev/null | grep -c \"Address.*10\\.\" || echo 0")
    local API_RESOLVES=$(run_on_vm "$WEB_IP" "nslookup api.internal.local 169.254.169.253 2>/dev/null | grep -c \"Address.*10\\.\" || echo 0")
    local DB_RESOLVES=$(run_on_vm "$WEB_IP" "nslookup db.internal.local 169.254.169.253 2>/dev/null | grep -c \"Address.*10\\.\" || echo 0")

    WEB_RESOLVES=${WEB_RESOLVES:-0}
    API_RESOLVES=${API_RESOLVES:-0}
    DB_RESOLVES=${DB_RESOLVES:-0}

    if [ "$WEB_RESOLVES" -ge 1 ] && [ "$API_RESOLVES" -ge 1 ] && [ "$DB_RESOLVES" -ge 1 ]; then
        INC_4522="resolved"
    else
        INC_4522="unresolved"
    fi
}

validate_inc_4523() {
    local WEB_TO_API=$(run_on_vm "$WEB_IP" "nc -zw3 $API_IP 8080 && echo 1 || echo 0")
    local API_TO_DB=$(run_on_vm "$API_IP" "nc -zw3 $DB_IP 5432 && echo 1 || echo 0")
    WEB_TO_API=${WEB_TO_API:-0}
    API_TO_DB=${API_TO_DB:-0}

    if [ "$WEB_TO_API" -eq 1 ] 2>/dev/null && [ "$API_TO_DB" -eq 1 ] 2>/dev/null; then
        INC_4523="resolved"
    else
        INC_4523="unresolved"
    fi
}

validate_inc_4524() {
    local ALL_PASS=true

    # Check 1: SSH source restriction (SG-scoped only; no CIDR)
    for SG_ID in "$WEB_SG_ID" "$API_SG_ID" "$DB_SG_ID"; do
        local SSH_CIDRS=$(aws ec2 describe-security-groups --group-ids "$SG_ID" \
            --query "SecurityGroups[0].IpPermissions[?FromPort==\`22\` && ToPort==\`22\`].IpRanges[].CidrIp" --output text 2>/dev/null)
        local SSH_SG_SOURCES=$(aws ec2 describe-security-groups --group-ids "$SG_ID" \
            --query "SecurityGroups[0].IpPermissions[?FromPort==\`22\` && ToPort==\`22\`].UserIdGroupPairs[].GroupId" --output text 2>/dev/null)

        if [ -n "$SSH_CIDRS" ] || [ -z "$SSH_SG_SOURCES" ]; then
            ALL_PASS=false
        fi

        if [ -n "$SSH_SG_SOURCES" ]; then
            for SRC_SG in $SSH_SG_SOURCES; do
                if [ "$SRC_SG" != "$BASTION_SG_ID" ]; then
                    ALL_PASS=false
                fi
            done
        fi
    done

    # Check 2: Database source restriction (API SG only, TCP/5432 only, SG-scoped)
    local DB_CIDRS=$(aws ec2 describe-security-groups --group-ids "$DB_SG_ID" \
        --query "SecurityGroups[0].IpPermissions[?IpProtocol=='tcp' && FromPort==\`5432\` && ToPort==\`5432\`].IpRanges[].CidrIp" --output text 2>/dev/null)
    local DB_SG_SOURCES=$(aws ec2 describe-security-groups --group-ids "$DB_SG_ID" \
        --query "SecurityGroups[0].IpPermissions[?IpProtocol=='tcp' && FromPort==\`5432\` && ToPort==\`5432\`].UserIdGroupPairs[].GroupId" --output text 2>/dev/null)
    local DB_WIDE_RULES=$(aws ec2 describe-security-groups --group-ids "$DB_SG_ID" \
        --query "SecurityGroups[0].IpPermissions[?IpProtocol=='tcp' && FromPort<=\`5432\` && ToPort>=\`5432\` && (FromPort!=\`5432\` || ToPort!=\`5432\`)]" --output text 2>/dev/null)

    if [ -n "$DB_WIDE_RULES" ]; then
        ALL_PASS=false
    fi

    if [ -n "$DB_CIDRS" ] || [ -z "$DB_SG_SOURCES" ]; then
        ALL_PASS=false
    fi

    if [ -n "$DB_SG_SOURCES" ]; then
        for SRC_SG in $DB_SG_SOURCES; do
            if [ "$SRC_SG" != "$API_SG_ID" ]; then
                ALL_PASS=false
            fi
        done
    fi

    # Check 3: ICMP restriction (SG-scoped only; no CIDR)
    local ICMP_CIDRS=$(aws ec2 describe-security-groups --group-ids "$WEB_SG_ID" \
        --query "SecurityGroups[0].IpPermissions[?IpProtocol==\`icmp\`].IpRanges[].CidrIp" --output text 2>/dev/null)
    local ICMP_SG_SOURCES=$(aws ec2 describe-security-groups --group-ids "$WEB_SG_ID" \
        --query "SecurityGroups[0].IpPermissions[?IpProtocol==\`icmp\`].UserIdGroupPairs[].GroupId" --output text 2>/dev/null)

    if [ -n "$ICMP_CIDRS" ] || [ -z "$ICMP_SG_SOURCES" ]; then
        ALL_PASS=false
    fi

    if [ -n "$ICMP_SG_SOURCES" ]; then
        for SRC_SG in $ICMP_SG_SOURCES; do
            if [ "$SRC_SG" != "$BASTION_SG_ID" ]; then
                ALL_PASS=false
            fi
        done
    fi

    if [ "$ALL_PASS" = true ]; then
        INC_4524="resolved"
    else
        INC_4524="unresolved"
    fi
}

# =============================================================================
# Token Generation
# =============================================================================

generate_verification_token() {
    local GITHUB_USER="$1"

    local TIMESTAMP=$(date +%s)
    local COMPLETION_DATE=$(date -u +"%Y-%m-%d")
    local COMPLETION_TIME=$(date -u +"%H:%M:%S")

    local VERIFICATION_SECRET=$(echo -n "${MASTER_SECRET}:${DEPLOYMENT_ID}" | sha256sum | cut -d' ' -f1)

    local PAYLOAD='{"github_username":"'"$GITHUB_USER"'","date":"'"$COMPLETION_DATE"'","time":"'"$COMPLETION_TIME"'","timestamp":'"$TIMESTAMP"',"challenge":"networking-lab-aws","challenges":4,"instance_id":"'"$DEPLOYMENT_ID"'"}'

    local SIGNATURE=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$VERIFICATION_SECRET" | cut -d' ' -f2)

    local TOKEN_DATA='{"payload":'"$PAYLOAD"',"signature":"'"$SIGNATURE"'"}'

    echo -n "$TOKEN_DATA" | base64 -w 0
}

# =============================================================================
# Display Results
# =============================================================================

show_status() {
    echo ""
    echo "============================================"
    echo "Incident Status"
    echo "============================================"

    local RESOLVED=0
    local TOTAL=4

    if [ "$INC_4521" == "resolved" ]; then
        echo -e "  ${GREEN}✓${NC} INC-4521"
        RESOLVED=$((RESOLVED + 1))
    else
        echo -e "  ${RED}✗${NC} INC-4521"
    fi

    if [ "$INC_4522" == "resolved" ]; then
        echo -e "  ${GREEN}✓${NC} INC-4522"
        RESOLVED=$((RESOLVED + 1))
    else
        echo -e "  ${RED}✗${NC} INC-4522"
    fi

    if [ "$INC_4523" == "resolved" ]; then
        echo -e "  ${GREEN}✓${NC} INC-4523"
        RESOLVED=$((RESOLVED + 1))
    else
        echo -e "  ${RED}✗${NC} INC-4523"
    fi

    if [ "$INC_4524" == "resolved" ]; then
        echo -e "  ${GREEN}✓${NC} INC-4524"
        RESOLVED=$((RESOLVED + 1))
    else
        echo -e "  ${RED}✗${NC} INC-4524"
    fi

    echo ""
    echo "  Resolved: $RESOLVED / $TOTAL"
    echo ""

    if [ $RESOLVED -eq $TOTAL ]; then
        echo -e "${GREEN}============================================${NC}"
        echo -e "${GREEN}   ALL INCIDENTS RESOLVED ${NC}"
        echo -e "${GREEN}============================================${NC}"
        echo ""
        echo -e "  Run ${CYAN}./validate.sh export${NC} to generate"
        echo "  your completion token."
        echo ""
    fi
}

export_token() {
    preflight_check > /dev/null 2>&1

    validate_inc_4521 > /dev/null 2>&1
    validate_inc_4522 > /dev/null 2>&1
    validate_inc_4523 > /dev/null 2>&1
    validate_inc_4524 > /dev/null 2>&1

    local RESOLVED=0
    [ "$INC_4521" == "resolved" ] && RESOLVED=$((RESOLVED + 1))
    [ "$INC_4522" == "resolved" ] && RESOLVED=$((RESOLVED + 1))
    [ "$INC_4523" == "resolved" ] && RESOLVED=$((RESOLVED + 1))
    [ "$INC_4524" == "resolved" ] && RESOLVED=$((RESOLVED + 1))

    if [ $RESOLVED -ne 4 ]; then
        echo -e "${RED}Error: Not all incidents resolved. Run './validate.sh' to see status.${NC}"
        exit 1
    fi

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}   NETWORKING LAB - EXPORT TOKEN${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""

    echo "Enter your GitHub username (must match your learntocloud.guide account):"
    echo -n "> "
    read GITHUB_USER

    if [ -z "$GITHUB_USER" ]; then
        echo -e "${RED}Error: GitHub username is required.${NC}"
        exit 1
    fi

    echo ""
    echo "Generating completion token..."
    echo ""

    local TOKEN=$(generate_verification_token "$GITHUB_USER")

    echo -e "${GREEN}Your completion token:${NC}"
    echo ""
    echo "TOKEN_START"
    echo "$TOKEN"
    echo "TOKEN_END"
    echo ""
    echo "Token details:"
    echo "  GitHub User: $GITHUB_USER"
    echo "  Instance ID: $DEPLOYMENT_ID"
    echo "  Completed:   $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo "  Challenge:   networking-lab-aws"
    echo ""
    echo -e "${CYAN}Submit this token at: https://learntocloud.guide/verify${NC}"
    echo ""
}

verify_token() {
    local TOKEN="$1"

    if [ -z "$TOKEN" ]; then
        echo "Usage: $0 verify <token>"
        exit 1
    fi

    echo ""
    echo "Verifying token..."
    echo ""

    local DECODED=$(echo "$TOKEN" | base64 -d 2>/dev/null)

    if [ -z "$DECODED" ]; then
        echo -e "${RED}Error: Invalid token format.${NC}"
        exit 1
    fi

    local PAYLOAD=$(echo "$DECODED" | jq -c '.payload' 2>/dev/null)
    local PROVIDED_SIG=$(echo "$DECODED" | jq -r '.signature' 2>/dev/null)
    local INSTANCE_ID=$(echo "$DECODED" | jq -r '.payload.instance_id' 2>/dev/null)

    if [ -z "$PAYLOAD" ] || [ "$PAYLOAD" == "null" ] || [ -z "$PROVIDED_SIG" ] || [ -z "$INSTANCE_ID" ]; then
        echo -e "${RED}Error: Could not parse token.${NC}"
        exit 1
    fi

    local VERIFICATION_SECRET=$(echo -n "${MASTER_SECRET}:${INSTANCE_ID}" | sha256sum | cut -d' ' -f1)
    local EXPECTED_SIG=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$VERIFICATION_SECRET" | cut -d' ' -f2)

    if [ "$PROVIDED_SIG" == "$EXPECTED_SIG" ]; then
        echo -e "${GREEN}✓ Token is VALID${NC}"
        echo ""
        echo "Token Details:"
        echo "$PAYLOAD" | jq .
    else
        echo -e "${RED}✗ Token is INVALID${NC}"
        echo "  Signature mismatch - token may have been tampered with."
        exit 1
    fi
}

# =============================================================================
# Main
# =============================================================================

usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  (default)   Check incident status"
    echo "  export      Generate completion token (after all incidents resolved)"
    echo "  verify      Verify a completion token"
    echo ""
    echo "Examples:"
    echo "  $0              # Check incident status"
    echo "  $0 export       # Generate completion token"
    echo "  $0 verify <token>"
}

main() {
    local TARGET="${1:-status}"

    case "$TARGET" in
        status|all)
            preflight_check
            validate_inc_4521
            validate_inc_4522
            validate_inc_4523
            validate_inc_4524
            show_status
            ;;
        export)
            export_token
            ;;
        verify)
            verify_token "$2"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown command: $TARGET"
            usage
            exit 1
            ;;
    esac

    echo ""
}

main "$@"
