#!/bin/bash
# =============================================================================
# NETWORKING LAB - VALIDATION SCRIPT
# Validates by testing actual connectivity, not resource configuration
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0

# Master secret for token generation (matches verification service)
MASTER_SECRET="L2C_NETLAB_MASTER_2024"

# SSH options for non-interactive use
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -q"
# Inner SSH options (simpler to avoid parsing issues)
INNER_SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -q"

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    echo ""
    echo "============================================"
    echo "$1"
    echo "============================================"
}

check_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    PASS=$((PASS + 1))
}

check_fail() {
    echo -e "  ${RED}✗${NC} $1"
    FAIL=$((FAIL + 1))
}

get_terraform_output() {
    cd "$TERRAFORM_DIR"
    terraform output -raw "$1" 2>/dev/null || echo ""
}

# Run a command on a VM via SSH through bastion
run_on_vm() {
    local TARGET_IP="$1"
    local CMD="$2"

    # Use simpler inner SSH options to avoid parsing issues in nested SSH
    ssh $SSH_OPTS -i "$SSH_KEY" labadmin@"$BASTION_IP" \
        "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null labadmin@$TARGET_IP '$CMD'" 2>/dev/null | tr -d '\n\r'
}

# =============================================================================
# Pre-flight checks
# =============================================================================

preflight_check() {
    print_header "Pre-flight Checks"

    # Check if terraform state exists
    if [ ! -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
        echo -e "${RED}Error: No terraform state found. Run 'terraform apply' first.${NC}"
        exit 1
    fi

    # Check for SSH key
    if [ ! -f "$HOME/.ssh/netlab-key" ]; then
        echo -e "${RED}Error: SSH key not found at ~/.ssh/netlab-key${NC}"
        echo "Run: terraform output -raw ssh_private_key > ~/.ssh/netlab-key && chmod 600 ~/.ssh/netlab-key"
        exit 1
    fi

    # Get outputs from terraform
    RESOURCE_GROUP=$(get_terraform_output "resource_group_name")
    DEPLOYMENT_ID=$(get_terraform_output "deployment_id")
    BASTION_IP=$(get_terraform_output "bastion_public_ip")
    API_IP=$(get_terraform_output "api_server_private_ip")
    WEB_IP=$(get_terraform_output "web_server_private_ip")
    DB_IP=$(get_terraform_output "database_server_private_ip")
    WEB_PUBLIC_IP=$(get_terraform_output "web_server_public_ip")
    SSH_KEY="$HOME/.ssh/netlab-key"

    if [ -z "$RESOURCE_GROUP" ] || [ -z "$BASTION_IP" ]; then
        echo -e "${RED}Error: Could not get terraform outputs. Is the infrastructure deployed?${NC}"
        exit 1
    fi

    check_pass "Terraform state exists"
    check_pass "SSH key found"
    check_pass "Bastion IP: $BASTION_IP"

    # Test bastion connectivity
    if ssh $SSH_OPTS -i "$SSH_KEY" labadmin@"$BASTION_IP" "echo ok" >/dev/null 2>&1; then
        check_pass "Bastion SSH accessible"
    else
        check_fail "Cannot SSH to bastion at $BASTION_IP"
        echo -e "${RED}Cannot continue without bastion access${NC}"
        exit 1
    fi

    # Export for other functions
    export RESOURCE_GROUP DEPLOYMENT_ID BASTION_IP API_IP WEB_IP DB_IP WEB_PUBLIC_IP SSH_KEY
}

# =============================================================================
# Task 1: Routing & Gateways
# Test: Can the API server reach the internet?
# =============================================================================

validate_task_1() {
    print_header "Task 1: Routing & Gateways"
    echo "  Testing: Can API server reach the internet?"

    # Test outbound internet connectivity from API server
    local RESULT=$(run_on_vm "$API_IP" "curl -s --max-time 10 -o /dev/null -w '%{http_code}' https://example.com 2>/dev/null || echo 'failed'")

    if [ "$RESULT" == "200" ]; then
        check_pass "API server can reach the internet (HTTP 200 from example.com)"
    else
        check_fail "API server cannot reach the internet (got: $RESULT)"
        echo "    The private subnet needs NAT Gateway for outbound internet access"
    fi
}

# =============================================================================
# Task 2: DNS Resolution
# Test: Can VMs resolve internal hostnames?
# =============================================================================

validate_task_2() {
    print_header "Task 2: DNS Resolution"
    echo "  Testing: Can VMs resolve internal DNS names?"

    # Test DNS resolution for each hostname using Azure DNS directly (168.63.129.16)
    # This bypasses systemd-resolved caching issues
    local WEB_RESOLVES=$(run_on_vm "$WEB_IP" "nslookup web.internal.local 168.63.129.16 2>/dev/null | grep -c 'Address.*10\.' || echo 0")
    local API_RESOLVES=$(run_on_vm "$WEB_IP" "nslookup api.internal.local 168.63.129.16 2>/dev/null | grep -c 'Address.*10\.' || echo 0")
    local DB_RESOLVES=$(run_on_vm "$WEB_IP" "nslookup db.internal.local 168.63.129.16 2>/dev/null | grep -c 'Address.*10\.' || echo 0")

    if [ "$WEB_RESOLVES" -ge 1 ]; then
        check_pass "web.internal.local resolves"
    else
        check_fail "web.internal.local does not resolve"
    fi

    if [ "$API_RESOLVES" -ge 1 ]; then
        check_pass "api.internal.local resolves"
    else
        check_fail "api.internal.local does not resolve"
    fi

    if [ "$DB_RESOLVES" -ge 1 ]; then
        check_pass "db.internal.local resolves"
    else
        check_fail "db.internal.local does not resolve"
    fi

    if [ "$WEB_RESOLVES" -lt 1 ] || [ "$API_RESOLVES" -lt 1 ] || [ "$DB_RESOLVES" -lt 1 ]; then
        echo "    Check: Is the Private DNS Zone linked to the VNet? Are A records created?"
    fi
}

# =============================================================================
# Task 3: Ports & Protocols
# Test: Can web reach API on 8080? Can API reach database on 5432?
# =============================================================================

validate_task_3() {
    print_header "Task 3: Ports & Protocols"
    echo "  Testing: Can services communicate on required ports?"

    # Test web -> API on port 8080 (use exit code instead of parsing output)
    local WEB_TO_API=$(run_on_vm "$WEB_IP" "nc -zw3 $API_IP 8080 && echo 1 || echo 0")
    WEB_TO_API=${WEB_TO_API:-0}

    if [ "$WEB_TO_API" -eq 1 ] 2>/dev/null; then
        check_pass "Web server can reach API server on port 8080"
    else
        check_fail "Web server cannot reach API server on port 8080"
        echo "    Check: API server NSG rules (priority matters!)"
    fi

    # Test API -> Database on port 5432
    local API_TO_DB=$(run_on_vm "$API_IP" "nc -zw3 $DB_IP 5432 && echo 1 || echo 0")
    API_TO_DB=${API_TO_DB:-0}

    if [ "$API_TO_DB" -ge 1 ] 2>/dev/null; then
        check_pass "API server can reach database on port 5432"
    else
        check_fail "API server cannot reach database on port 5432"
        echo "    Check: Database NSG rule - is it Allow or Deny?"
    fi
}

# =============================================================================
# Task 4: Security Hardening
# Test: SSH restricted? Database access restricted?
# =============================================================================

validate_task_4() {
    print_header "Task 4: Security Hardening"
    echo "  Testing: Are security restrictions in place?"

    # Test 1: Direct SSH to web server should be blocked (not from bastion subnet)
    # We test by checking NSG rules since we can't easily test from outside
    local WEB_NSG="nsg-web-${DEPLOYMENT_ID}"
    local SSH_SOURCE=$(az network nsg rule show -g "$RESOURCE_GROUP" \
        --nsg-name "$WEB_NSG" -n allow-ssh \
        --query "sourceAddressPrefix" -o tsv 2>/dev/null || echo "*")

    if [ "$SSH_SOURCE" != "*" ] && [ "$SSH_SOURCE" != "0.0.0.0/0" ] && [ "$SSH_SOURCE" != "Internet" ]; then
        check_pass "Web server SSH restricted (source: $SSH_SOURCE)"
    else
        check_fail "Web server SSH open to internet (source: $SSH_SOURCE)"
        echo "    Should be restricted to bastion subnet (10.0.1.0/24)"
    fi

    # Test 2: Database should only accept connections from API subnet
    local DB_NSG="nsg-database-${DEPLOYMENT_ID}"
    local PG_SOURCE=$(az network nsg rule show -g "$RESOURCE_GROUP" \
        --nsg-name "$DB_NSG" -n postgres-access \
        --query "sourceAddressPrefix" -o tsv 2>/dev/null || echo "")

    if [ "$PG_SOURCE" == "10.0.2.0/24" ]; then
        check_pass "Database access restricted to API subnet only"
    elif [ "$PG_SOURCE" == "10.0.0.0/16" ]; then
        check_fail "Database open to entire VNet (should be API subnet 10.0.2.0/24 only)"
    else
        check_fail "Database access not properly restricted (source: $PG_SOURCE)"
    fi

    # Test 3: Bastion should NOT be able to reach database (it's not in API subnet)
    local BASTION_TO_DB=$(ssh $SSH_OPTS -i "$SSH_KEY" labadmin@"$BASTION_IP" \
        "nc -zv $DB_IP 5432 -w 3 2>&1 | grep -c 'succeeded\|open' || echo 0" 2>/dev/null | tr -d '\n\r')

    if [ "$BASTION_TO_DB" -eq 0 ] 2>/dev/null; then
        check_pass "Bastion cannot reach database (correct - least privilege)"
    else
        check_fail "Bastion can reach database (should be blocked - not in API subnet)"
    fi

    # Test 4: ICMP not open from anywhere
    local ICMP_SOURCE=$(az network nsg rule show -g "$RESOURCE_GROUP" \
        --nsg-name "$WEB_NSG" -n allow-icmp \
        --query "sourceAddressPrefix" -o tsv 2>/dev/null || echo "deleted")

    if [ "$ICMP_SOURCE" == "*" ]; then
        check_fail "ICMP open from anywhere (should be VNet only or removed)"
    else
        check_pass "ICMP properly restricted (source: $ICMP_SOURCE)"
    fi
}

# =============================================================================
# Token Generation
# =============================================================================

generate_verification_token() {
    local GITHUB_USER="$1"

    # Get current timestamp
    local TIMESTAMP=$(date +%s)
    local COMPLETION_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Derive verification secret from master secret + instance ID
    local VERIFICATION_SECRET=$(echo -n "${MASTER_SECRET}${DEPLOYMENT_ID}" | sha256sum | cut -d' ' -f1)

    # Create payload
    local PAYLOAD=$(cat <<EOF
{
    "github_username": "${GITHUB_USER}",
    "completion_date": "${COMPLETION_DATE}",
    "timestamp": ${TIMESTAMP},
    "challenge": "networking-lab-azure",
    "tasks_completed": 4,
    "instance_id": "${DEPLOYMENT_ID}",
    "resource_group": "${RESOURCE_GROUP}"
}
EOF
)

    # Generate HMAC-SHA256 signature
    local SIGNATURE=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$VERIFICATION_SECRET" | cut -d' ' -f2)

    # Create final token structure
    local TOKEN_DATA=$(cat <<EOF
{
    "payload": $(echo "$PAYLOAD" | jq -c .),
    "signature": "${SIGNATURE}"
}
EOF
)

    # Base64 encode the token
    echo "$TOKEN_DATA" | jq -c . | base64 -w 0
}

# =============================================================================
# Completion and Token Export
# =============================================================================

generate_token() {
    print_header "Completion Status"

    local TOTAL=$((PASS + FAIL))
    echo ""
    echo "  Passed: $PASS / $TOTAL"
    echo "  Failed: $FAIL"
    echo ""

    if [ $FAIL -eq 0 ]; then
        echo -e "${GREEN}============================================${NC}"
        echo -e "${GREEN}   ALL TASKS COMPLETED! ${NC}"
        echo -e "${GREEN}============================================${NC}"
        echo ""
        echo -e "  Run ${CYAN}../scripts/validate.sh export${NC} to generate"
        echo "  your verifiable completion token."
        echo ""
    else
        echo -e "${YELLOW}Keep going! Fix the failing checks and run validation again.${NC}"
    fi
}

export_token() {
    # Run validation first (silently check)
    preflight_check > /dev/null 2>&1

    # Run all validations and count
    PASS=0
    FAIL=0

    validate_task_1 > /dev/null 2>&1
    validate_task_2 > /dev/null 2>&1
    validate_task_3 > /dev/null 2>&1
    validate_task_4 > /dev/null 2>&1

    if [ $FAIL -ne 0 ]; then
        echo -e "${RED}Error: Not all tasks are completed. Run './validate.sh all' to see status.${NC}"
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
    local TOKEN=$(generate_verification_token "$GITHUB_USER")

    echo -e "${GREEN}Your completion token:${NC}"
    echo ""
    echo "============================================"
    echo "$TOKEN"
    echo "============================================"
    echo ""
    echo "Token details:"
    echo "  GitHub User: $GITHUB_USER"
    echo "  Instance ID: $DEPLOYMENT_ID"
    echo "  Completed:   $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo "  Challenge:   networking-lab-azure"
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
    local DECODED=$(echo "$TOKEN" | base64 -d 2>/dev/null)

    if [ -z "$DECODED" ]; then
        echo -e "${RED}Error: Invalid token format.${NC}"
        exit 1
    fi

    # Extract payload and signature
    local PAYLOAD=$(echo "$DECODED" | jq -r '.payload' 2>/dev/null)
    local PROVIDED_SIG=$(echo "$DECODED" | jq -r '.signature' 2>/dev/null)
    local INSTANCE_ID=$(echo "$PAYLOAD" | jq -r '.instance_id' 2>/dev/null)

    if [ -z "$PAYLOAD" ] || [ -z "$PROVIDED_SIG" ] || [ -z "$INSTANCE_ID" ]; then
        echo -e "${RED}Error: Could not parse token.${NC}"
        exit 1
    fi

    # Derive verification secret
    local VERIFICATION_SECRET=$(echo -n "${MASTER_SECRET}${INSTANCE_ID}" | sha256sum | cut -d' ' -f1)

    # Regenerate signature
    local EXPECTED_SIG=$(echo -n "$PAYLOAD" | jq -c . | openssl dgst -sha256 -hmac "$VERIFICATION_SECRET" | cut -d' ' -f2)

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
    echo "  task-1    Validate Task 1: Routing & Gateways"
    echo "  task-2    Validate Task 2: DNS Resolution"
    echo "  task-3    Validate Task 3: Ports & Protocols"
    echo "  task-4    Validate Task 4: Security Hardening"
    echo "  all       Validate all tasks (default)"
    echo "  export    Generate completion token (after all tasks pass)"
    echo "  verify    Verify a completion token"
    echo ""
    echo "Examples:"
    echo "  $0 task-1           # Validate Task 1 only"
    echo "  $0 all              # Validate all tasks"
    echo "  $0 export           # Generate completion token"
    echo "  $0 verify <token>   # Verify a token"
}

main() {
    local TARGET="${1:-all}"

    case "$TARGET" in
        task-1)
            preflight_check
            validate_task_1
            ;;
        task-2)
            preflight_check
            validate_task_2
            ;;
        task-3)
            preflight_check
            validate_task_3
            ;;
        task-4)
            preflight_check
            validate_task_4
            ;;
        all)
            preflight_check
            validate_task_1
            validate_task_2
            validate_task_3
            validate_task_4
            generate_token
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
