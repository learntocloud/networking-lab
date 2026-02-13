#!/bin/bash
# =============================================================================
# NETWORKING LAB - VALIDATION SCRIPT (GCP)
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

# Incident tracking (POSIX-friendly)
INC_4521="pending"
INC_4522="pending"
INC_4523="pending"
INC_4524="pending"

# Master secret for token generation (matches verification service)
MASTER_SECRET="L2C_CTF_MASTER_2024"

# SSH options for non-interactive use
SSH_OPTS="-n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -q"
ADMIN_USERNAME="labadmin"

# =============================================================================
# Helper Functions
# =============================================================================

get_terraform_output() {
    cd "$TERRAFORM_DIR"
    terraform output -raw "$1" 2>/dev/null || echo ""
}

base64_encode_no_wrap() {
    if printf "test" | base64 -w 0 >/dev/null 2>&1; then
        printf '%s' "$1" | base64 -w 0
    else
        printf '%s' "$1" | base64 | tr -d '\n'
    fi
}

base64_decode_stdin() {
    if printf "dGVzdA==" | base64 -d >/dev/null 2>&1; then
        base64 -d
    else
        base64 -D
    fi
}

sha256_hex() {
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
    else
        printf '%s' "$1" | openssl dgst -sha256 | awk '{print $NF}'
    fi
}

# Run a command on a VM via SSH through bastion
run_on_vm() {
    local TARGET_IP="$1"
    local CMD="$2"
    local CMD_B64

    CMD_B64=$(base64_encode_no_wrap "$CMD")

    ssh $SSH_OPTS -i "$SSH_KEY" "${ADMIN_USERNAME}@${BASTION_IP}" \
        "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${ADMIN_USERNAME}@${TARGET_IP} \"printf '%s' '$CMD_B64' | (base64 -d 2>/dev/null || base64 --decode 2>/dev/null) | bash\"" \
        2>/dev/null | tr -d '\n\r'
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

    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        echo -e "${RED}Error: gcloud CLI not found.${NC}"
        exit 1
    fi

    # Check required local tools
    local REQUIRED_CMDS=("terraform" "ssh" "jq" "openssl" "base64")
    local cmd
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${RED}Error: Required command '$cmd' not found in PATH.${NC}"
            exit 1
        fi
    done
    # Ensure at least one SHA-256 implementation is available
    if ! command -v sha256sum >/dev/null 2>&1 && \
       ! command -v shasum >/dev/null 2>&1 && \
       ! command -v openssl >/dev/null 2>&1; then
        echo -e "${RED}Error: Required command for SHA-256 ('sha256sum', 'shasum', or 'openssl') not found in PATH.${NC}"
        exit 1
    fi

    # Get outputs from terraform
    PROJECT_ID=$(get_terraform_output "project_id")
    DEPLOYMENT_ID=$(get_terraform_output "deployment_id")
    BASTION_IP=$(get_terraform_output "bastion_public_ip")
    API_IP=$(get_terraform_output "api_server_private_ip")
    WEB_IP=$(get_terraform_output "web_server_private_ip")
    DB_IP=$(get_terraform_output "database_server_private_ip")
    SSH_KEY="$HOME/.ssh/netlab-key"

    if [ -z "$PROJECT_ID" ] || [ -z "$BASTION_IP" ]; then
        echo -e "${RED}Error: Could not get terraform outputs. Is the infrastructure deployed?${NC}"
        exit 1
    fi

    # Test bastion connectivity
    if ! ssh $SSH_OPTS -i "$SSH_KEY" "${ADMIN_USERNAME}@${BASTION_IP}" "echo ok" >/dev/null 2>&1; then
        echo -e "${RED}Error: Cannot reach bastion host${NC}"
        exit 1
    fi

    # Export for other functions
    export PROJECT_ID DEPLOYMENT_ID BASTION_IP API_IP WEB_IP DB_IP SSH_KEY
}

# =============================================================================
# Incident Validation
# =============================================================================

validate_inc_4521() {
    local RESULT
    RESULT=$(run_on_vm "$API_IP" "curl -s --max-time 10 -o /dev/null -w '%{http_code}' https://example.com 2>/dev/null || echo 'failed'")
    if [ "$RESULT" == "200" ]; then
        INC_4521="resolved"
    else
        INC_4521="unresolved"
    fi
}

validate_inc_4522() {
    local WEB_RESOLVES
    local API_RESOLVES
    local DB_RESOLVES

    WEB_RESOLVES=$(run_on_vm "$WEB_IP" "nslookup web.internal.local 169.254.169.254 2>/dev/null | grep -c 'Address.*10\.' || echo 0")
    API_RESOLVES=$(run_on_vm "$WEB_IP" "nslookup api.internal.local 169.254.169.254 2>/dev/null | grep -c 'Address.*10\.' || echo 0")
    DB_RESOLVES=$(run_on_vm "$WEB_IP" "nslookup db.internal.local 169.254.169.254 2>/dev/null | grep -c 'Address.*10\.' || echo 0")

    if [ "$WEB_RESOLVES" -ge 1 ] && [ "$API_RESOLVES" -ge 1 ] && [ "$DB_RESOLVES" -ge 1 ]; then
        INC_4522="resolved"
    else
        INC_4522="unresolved"
    fi
}

validate_inc_4523() {
    local WEB_TO_API
    local API_TO_DB

    WEB_TO_API=$(run_on_vm "$WEB_IP" "nc -zw3 $API_IP 8080 && echo 1 || echo 0")
    API_TO_DB=$(run_on_vm "$API_IP" "nc -zw3 $DB_IP 5432 && echo 1 || echo 0")

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

    # Check 1: SSH source restriction
    local SSH_WORLD=0
    for RULE in "allow-ssh-bastion-${DEPLOYMENT_ID}" "allow-ssh-web-${DEPLOYMENT_ID}" "allow-ssh-api-${DEPLOYMENT_ID}" "allow-ssh-db-${DEPLOYMENT_ID}"; do
        local SSH_SOURCE
        SSH_SOURCE=$(gcloud compute firewall-rules describe "$RULE" \
            --project "$PROJECT_ID" --format="value(sourceRanges)" 2>/dev/null || echo "*")
        if echo "$SSH_SOURCE" | grep -q "0.0.0.0/0"; then
            SSH_WORLD=1
        fi
    done

    if [ "$SSH_WORLD" -ne 0 ]; then
        ALL_PASS=false
    fi

    # Check 2: Database source restriction
    local PG_SOURCE
    PG_SOURCE=$(gcloud compute firewall-rules describe "allow-postgres-${DEPLOYMENT_ID}" \
        --project "$PROJECT_ID" --format="value(sourceRanges)" 2>/dev/null || echo "")

    if ! echo "$PG_SOURCE" | grep -q "10.0.2.0/24"; then
        ALL_PASS=false
    fi

    # Check 3: ICMP restriction
    local ICMP_SOURCE
    ICMP_SOURCE=$(gcloud compute firewall-rules describe "allow-icmp-${DEPLOYMENT_ID}" \
        --project "$PROJECT_ID" --format="value(sourceRanges)" 2>/dev/null || echo "*")

    if echo "$ICMP_SOURCE" | grep -q "0.0.0.0/0"; then
        ALL_PASS=false
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

    # Get current timestamp
    local TIMESTAMP
    local COMPLETION_DATE
    local COMPLETION_TIME

    TIMESTAMP=$(date +%s)
    COMPLETION_DATE=$(date -u +"%Y-%m-%d")
    COMPLETION_TIME=$(date -u +"%H:%M:%S")

    # Derive verification secret from master secret + instance ID
    local VERIFICATION_SECRET
    VERIFICATION_SECRET=$(sha256_hex "${MASTER_SECRET}:${DEPLOYMENT_ID}")

    # Create payload as single-line JSON
    local PAYLOAD
    PAYLOAD='{"github_username":"'"$GITHUB_USER"'","date":"'"$COMPLETION_DATE"'","time":"'"$COMPLETION_TIME"'","timestamp":'"$TIMESTAMP"',"challenge":"networking-lab-gcp","challenges":4,"instance_id":"'"$DEPLOYMENT_ID"'"}'

    # Generate HMAC-SHA256 signature
    local SIGNATURE
    SIGNATURE=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$VERIFICATION_SECRET" | cut -d' ' -f2)

    # Create final token structure
    local TOKEN_DATA
    TOKEN_DATA='{"payload":'"$PAYLOAD"',"signature":"'"$SIGNATURE"'"}'

    # Base64 encode the token
    base64_encode_no_wrap "$TOKEN_DATA"
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
    # Run validation first (silently check)
    preflight_check > /dev/null 2>&1

    # Run all validations
    validate_inc_4521 > /dev/null 2>&1
    validate_inc_4522 > /dev/null 2>&1
    validate_inc_4523 > /dev/null 2>&1
    validate_inc_4524 > /dev/null 2>&1

    # Check if all resolved
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

    # Get GitHub username
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

    # Generate the token
    local TOKEN
    TOKEN=$(generate_verification_token "$GITHUB_USER")

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
    echo "  Challenge:   networking-lab-gcp"
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

    # Decode the token
    local DECODED
    DECODED=$(echo "$TOKEN" | base64_decode_stdin 2>/dev/null)

    if [ -z "$DECODED" ]; then
        echo -e "${RED}Error: Invalid token format.${NC}"
        exit 1
    fi

    # Extract payload as compact JSON
    local PAYLOAD
    local PROVIDED_SIG
    local INSTANCE_ID

    PAYLOAD=$(echo "$DECODED" | jq -c '.payload' 2>/dev/null)
    PROVIDED_SIG=$(echo "$DECODED" | jq -r '.signature' 2>/dev/null)
    INSTANCE_ID=$(echo "$DECODED" | jq -r '.payload.instance_id' 2>/dev/null)

    if [ -z "$PAYLOAD" ] || [ "$PAYLOAD" == "null" ] || [ -z "$PROVIDED_SIG" ] || [ -z "$INSTANCE_ID" ]; then
        echo -e "${RED}Error: Could not parse token.${NC}"
        exit 1
    fi

    # Derive verification secret
    local VERIFICATION_SECRET
    VERIFICATION_SECRET=$(sha256_hex "${MASTER_SECRET}:${INSTANCE_ID}")

    # Regenerate signature over the exact payload string
    local EXPECTED_SIG
    EXPECTED_SIG=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$VERIFICATION_SECRET" | cut -d' ' -f2)

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
