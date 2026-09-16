#!/bin/bash
# =============================================================================
# NETWORKING LAB - VALIDATION SCRIPT (GCP)
# Validates incident resolution by testing actual connectivity
# =============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/../../scripts/dns-validation.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Incident tracking (POSIX-friendly)
INC_4521="pending"
INC_4522="pending"
INC_4523="pending"
INC_4524="pending"

# Master secret for token generation (matches verification service)
MASTER_SECRET="L2C_CTF_MASTER_2024"

# =============================================================================
# Helper Functions
# =============================================================================

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

# =============================================================================
# Pre-flight checks
# =============================================================================

preflight_check() {
    require_commands gcloud terraform ssh jq python3 curl openssl base64
    # Check if terraform state exists
    if [ ! -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
        echo -e "${RED}Error: No terraform state found. Run './setup.sh' first.${NC}"
        exit 2
    fi

    # Check for SSH key
    if [ ! -f "$HOME/.ssh/netlab-key" ]; then
        echo -e "${RED}Error: SSH key not found at ~/.ssh/netlab-key${NC}"
        echo "Run: cd ../terraform && terraform output -raw ssh_private_key > ~/.ssh/netlab-key && chmod 600 ~/.ssh/netlab-key"
        exit 2
    fi

    load_lab_outputs
    local IP
    for IP in "$BASTION_IP" "$WEB_IP" "$API_IP" "$DB_IP"; do
        if ! check_vm_tools "$IP"; then
            echo "Error: Cannot run validation on $IP; check SSH and diagnostic tools." >&2
            exit 2
        fi
    done
}

# =============================================================================
# Incident Validation
# =============================================================================

validate_inc_4521() {
    local STATUS=0
    check_api_egress || STATUS=$?
    record_incident INC_4521 "$STATUS" "$EGRESS_DETAIL"
}

validate_inc_4522() {
    local ATTEMPT STATUS
    for ATTEMPT in {1..3}; do
        STATUS=0
        validate_private_dns "169.254.169.254" "$BASTION_IP" "$WEB_IP" "$API_IP" "$DB_IP" || STATUS=$?
        if [ "$STATUS" -ne 1 ]; then break; fi
        if [ "$ATTEMPT" -lt 3 ]; then sleep 2; fi
    done
    record_incident INC_4522 "$STATUS" "$DNS_DETAIL"
}

validate_inc_4523() {
    local STATUS=0
    check_application_paths || STATUS=$?
    record_incident INC_4523 "$STATUS" "$PORTS_DETAIL"
}

validate_inc_4524() {
    local STATUS=0
    check_hardening || STATUS=$?
    record_incident INC_4524 "$STATUS" "$HARDENING_DETAIL"
}

record_incident() {
    case "$2" in
        0) printf -v "$1" '%s' resolved ;;
        1) printf -v "$1" '%s' unresolved ;;
        *) printf -v "$1" '%s' error; echo "Error: $1: $3" >&2 ;;
    esac
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
    echo "  INC-4521 ($INC_4521): $EGRESS_DETAIL"
    echo "  INC-4522 ($INC_4522): $DNS_DETAIL"
    echo "  INC-4523 ($INC_4523): $PORTS_DETAIL"
    echo "  INC-4524 ($INC_4524): $HARDENING_DETAIL"
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
    if [[ " $INC_4521 $INC_4522 $INC_4523 $INC_4524 " == *" error "* ]]; then return 2; fi
    [ "$RESOLVED" -eq "$TOTAL" ]
}

export_token() {
    preflight_check

    # Run all validations
    validate_inc_4521
    validate_inc_4522
    validate_inc_4523
    validate_inc_4524
    if [[ " $INC_4521 $INC_4522 $INC_4523 $INC_4524 " == *" error "* ]]; then
        echo "Error: Validation could not complete; no token was generated." >&2
        exit 2
    fi

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
    echo -e "${CYAN}Submit this token at: https://learntocloud.guide/phase/2${NC}"
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

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
