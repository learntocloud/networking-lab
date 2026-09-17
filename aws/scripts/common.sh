#!/bin/bash
# Shared helpers for the AWS networking lab setup and validation scripts.
# shellcheck disable=SC2034  # detail/state variables are consumed by the sourcing scripts
# Checks return 0 (pass), 1 (unresolved), or 2 (execution/service error).

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=10 -o ConnectionAttempts=1 -o BatchMode=yes
    -o ControlMaster=no -o ControlPath=none
    -o ServerAliveInterval=10 -o ServerAliveCountMax=3 -q)

EGRESS_DETAIL=""
PORTS_DETAIL=""
HARDENING_DETAIL=""
SERVICE_DETAIL=""

require_commands() {
    local COMMAND
    for COMMAND in "$@"; do
        if ! command -v "$COMMAND" >/dev/null 2>&1; then
            echo "Error: Required command '$COMMAND' is not installed." >&2
            return 2
        fi
    done
}

get_terraform_output() {
    terraform -chdir="$TERRAFORM_DIR" output -raw "$1"
}

load_lab_outputs() {
    DEPLOYMENT_ID=$(get_terraform_output deployment_id) || return 2
    REGION=$(get_terraform_output region) || return 2
    VPC_ID=$(get_terraform_output vpc_id) || return 2
    ADMIN_USERNAME=$(get_terraform_output admin_username) || return 2
    BASTION_IP=$(get_terraform_output bastion_public_ip) || return 2
    BASTION_PRIVATE_IP=$(get_terraform_output bastion_private_ip) || return 2
    WEB_IP=$(get_terraform_output web_server_private_ip) || return 2
    WEB_PUBLIC_IP=$(get_terraform_output web_server_public_ip) || return 2
    API_IP=$(get_terraform_output api_server_private_ip) || return 2
    DB_IP=$(get_terraform_output database_server_private_ip) || return 2
    BASTION_INSTANCE_ID=$(get_terraform_output bastion_instance_id) || return 2
    WEB_INSTANCE_ID=$(get_terraform_output web_instance_id) || return 2
    API_INSTANCE_ID=$(get_terraform_output api_instance_id) || return 2
    DB_INSTANCE_ID=$(get_terraform_output database_instance_id) || return 2
    PRIVATE_ROUTE_TABLE_ID=$(get_terraform_output private_route_table_id) || return 2
    NAT_GATEWAY_ID=$(get_terraform_output nat_gateway_id) || return 2
    DNS_ZONE_ID=$(get_terraform_output dns_zone_id) || return 2
    SSH_KEY="$HOME/.ssh/netlab-key"
    if [ -z "$DEPLOYMENT_ID" ] || [ -z "$REGION" ] || [ -z "$VPC_ID" ] ||
        [ -z "$ADMIN_USERNAME" ] || [ -z "$BASTION_IP" ] || [ -z "$BASTION_PRIVATE_IP" ] ||
        [ -z "$WEB_IP" ] || [ -z "$WEB_PUBLIC_IP" ] || [ -z "$API_IP" ] || [ -z "$DB_IP" ] ||
        [ -z "$BASTION_INSTANCE_ID" ] || [ -z "$WEB_INSTANCE_ID" ] ||
        [ -z "$API_INSTANCE_ID" ] || [ -z "$DB_INSTANCE_ID" ] ||
        [ -z "$PRIVATE_ROUTE_TABLE_ID" ] || [ -z "$NAT_GATEWAY_ID" ] || [ -z "$DNS_ZONE_ID" ]; then
        echo "Error: Terraform outputs are incomplete. Finish setup first." >&2
        return 2
    fi
}

aws_json() {
    aws --region "$REGION" --output json "$@"
}

run_on_vm() {
    local TARGET_IP="$1" COMMAND PROXY
    local -a HOP=("${SSH_OPTS[@]}" -i "$SSH_KEY")
    printf -v COMMAND '%q' "$2"
    if [ "$TARGET_IP" != "$BASTION_IP" ]; then
        printf -v PROXY '%q ' ssh "${SSH_OPTS[@]}" -i "$SSH_KEY" \
            -W '%h:%p' "$ADMIN_USERNAME@$BASTION_IP"
        HOP+=(-o "ProxyCommand=$PROXY")
    fi
    ssh -n "${HOP[@]}" "$ADMIN_USERNAME@$TARGET_IP" \
        "timeout ${3:-60} bash -o pipefail -c $COMMAND"
}

check_vm_tools() {
    run_on_vm "$1" '
        for TOOL in curl python3 nc dig getent timeout jq sort grep cut ping; do
            command -v "$TOOL" >/dev/null || {
                echo "Error: Required diagnostic tool $TOOL is missing." >&2
                exit 127
            }
        done
    '
}

# Local TCP connect test from the validation client: 0 open, 1 blocked, 2 error.
tcp_probe_local() {
    python3 - "$1" "$2" <<'PYPROBE'
import socket
import sys

try:
    with socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=5):
        sys.exit(0)
except (socket.timeout, ConnectionRefusedError, ConnectionResetError, TimeoutError):
    sys.exit(1)
except OSError as error:
    # EHOSTUNREACH/ENETUNREACH also mean the path is blocked.
    sys.exit(1 if error.errno in (110, 111, 113, 101) else 2)
PYPROBE
}

probe_api_https() {
    local RESPONSE STATUS
    if RESPONSE=$(run_on_vm "$API_IP" \
        'curl -4 --noproxy "*" -fsSL --max-redirs 3 --connect-timeout 5 --max-time 10 --retry 2 --retry-all-errors --retry-delay 2 --retry-max-time 35 -o /dev/null -w "%{http_code}" https://example.com' 50); then
        if [[ "$RESPONSE" == 2[0-9][0-9] ]]; then return 0; fi
        EGRESS_DETAIL="External HTTPS returned unexpected status $RESPONSE."
        return 2
    else
        STATUS=$?
    fi
    EGRESS_DETAIL="API external HTTPS failed (exit $STATUS)."
    case "$STATUS" in
        7|28) return 1 ;;
        *) EGRESS_DETAIL+=" Check SSH, tools, public DNS, TLS, and the external endpoint."; return 2 ;;
    esac
}

# Resolve the route table that actually applies to a subnet (explicit or main).
effective_route_table() {
    local SUBNET_ID="$1" TABLE
    TABLE=$(aws_json ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.subnet-id,Values=$SUBNET_ID" \
        --query 'RouteTables[0]') || return 2
    if [ "$TABLE" = null ]; then
        TABLE=$(aws_json ec2 describe-route-tables \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" \
            --query 'RouteTables[0]') || return 2
    fi
    if [ "$TABLE" = null ]; then return 2; fi
    printf '%s' "$TABLE"
}

check_api_egress() {
    local ENI SUBNET_ID TABLE TABLE_ID ROUTE NAT_ID NAT NAT_IPS OUTBOUND_IP
    EGRESS_DETAIL=""
    if ! check_vm_tools "$API_IP"; then
        EGRESS_DETAIL="Cannot reach the API over SSH or diagnostic tools are missing."
        return 2
    fi
    if ! ENI=$(aws_json ec2 describe-network-interfaces \
        --filters "Name=attachment.instance-id,Values=$API_INSTANCE_ID" \
        --query 'NetworkInterfaces'); then
        EGRESS_DETAIL="Cannot read the API network interfaces from AWS."
        return 2
    fi
    if ! jq -e 'length == 1 and (.[0].Ipv6Addresses | length == 0) and
            (.[0].PrivateIpAddresses | length == 1)' <<< "$ENI" >/dev/null; then
        EGRESS_DETAIL="Only the lab single-interface, primary-IPv4 API topology is supported."
        return 2
    fi
    if jq -e '.[0].Association.PublicIp != null' <<< "$ENI" >/dev/null; then
        EGRESS_DETAIL="The API must stay private; a public IP is not a NAT gateway repair."
        return 1
    fi
    SUBNET_ID=$(jq -r '.[0].SubnetId' <<< "$ENI")
    if ! TABLE=$(effective_route_table "$SUBNET_ID"); then
        EGRESS_DETAIL="Cannot determine the route table that applies to the API subnet."
        return 2
    fi
    TABLE_ID=$(jq -r '.RouteTableId' <<< "$TABLE")
    ROUTE=$(jq -c '[.Routes[] | select(.DestinationCidrBlock == "0.0.0.0/0")] | .[0]' <<< "$TABLE")
    if [ "$ROUTE" = null ]; then
        EGRESS_DETAIL="Route table $TABLE_ID for the API subnet has no 0.0.0.0/0 route."
        return 1
    fi
    if [ "$(jq -r '.State' <<< "$ROUTE")" != active ]; then
        EGRESS_DETAIL="The API subnet's 0.0.0.0/0 route in $TABLE_ID is not active (blackhole)."
        return 1
    fi
    NAT_ID=$(jq -r '.NatGatewayId // empty' <<< "$ROUTE")
    if [ -z "$NAT_ID" ]; then
        EGRESS_DETAIL="The API subnet's 0.0.0.0/0 route in $TABLE_ID does not target a NAT gateway; the API must stay private."
        return 1
    fi
    if ! NAT=$(aws_json ec2 describe-nat-gateways \
        --filter "Name=nat-gateway-id,Values=$NAT_ID" --query 'NatGateways[0]'); then
        EGRESS_DETAIL="Cannot read NAT gateway $NAT_ID from AWS."
        return 2
    fi
    if [ "$NAT" = null ] || [ "$(jq -r '.VpcId' <<< "$NAT")" != "$VPC_ID" ]; then
        EGRESS_DETAIL="NAT gateway $NAT_ID is not in the lab VPC."
        return 1
    fi
    if [ "$(jq -r '.State' <<< "$NAT")" != available ] ||
        [ "$(jq -r '.ConnectivityType // "public"' <<< "$NAT")" != public ]; then
        EGRESS_DETAIL="NAT gateway $NAT_ID is not an available public NAT gateway."
        return 1
    fi
    NAT_IPS=$(jq -r '[.NatGatewayAddresses[]? | .PublicIp | select(. != null)] | unique | join(" ")' <<< "$NAT")
    if [ -z "$NAT_IPS" ]; then
        EGRESS_DETAIL="NAT gateway $NAT_ID has no public IPv4 address."
        return 1
    fi
    probe_api_https || return $?
    if ! OUTBOUND_IP=$(run_on_vm "$API_IP" \
        'curl -4 --noproxy "*" -fsS --connect-timeout 5 --max-time 10 --retry 2 --retry-all-errors --retry-delay 2 --retry-max-time 35 https://api.ipify.org' 50); then
        EGRESS_DETAIL="Could not obtain the API outbound IP from api.ipify.org."
        return 2
    fi
    if [ -z "$OUTBOUND_IP" ] || [[ " $NAT_IPS " != *" $OUTBOUND_IP "* ]]; then
        EGRESS_DETAIL="Observed outbound IP $OUTBOUND_IP is not an address of NAT gateway $NAT_ID."
        return 1
    fi
    EGRESS_DETAIL="External HTTPS works through NAT gateway $NAT_ID (outbound IP $OUTBOUND_IP)."
}

probe_api_health() {
    local SOURCE="$1" TARGET="$2" RESPONSE STATUS
    if RESPONSE=$(run_on_vm "$SOURCE" \
        "curl --noproxy '*' -fsS --connect-timeout 3 --max-time 5 http://$TARGET:8080/health" 15); then
        if jq -se 'length == 1 and (.[0] | type == "object" and .status == "healthy")' \
            <<< "$RESPONSE" >/dev/null 2>&1; then
            SERVICE_DETAIL="API health on $TARGET:8080 is healthy."
            return 0
        fi
        SERVICE_DETAIL="The endpoint on $TARGET:8080 did not return healthy API JSON."
        return 2
    else
        STATUS=$?
    fi
    SERVICE_DETAIL="$SOURCE cannot verify API health on $TARGET:8080 (exit $STATUS)."
    case "$STATUS" in 7|28) return 1 ;; *) return 2 ;; esac
}

probe_postgres() {
    local SOURCE="$1" TARGET="$2" STATUS
    if run_on_vm "$SOURCE" "pg_isready -q -h $TARGET -p 5432 -U labuser -d labdb -t 3" 15; then
        SERVICE_DETAIL="PostgreSQL on $TARGET:5432 is accepting connections."
        return 0
    else
        STATUS=$?
    fi
    SERVICE_DETAIL="$SOURCE could not confirm PostgreSQL readiness on $TARGET:5432 (exit $STATUS)."
    if [ "$STATUS" -eq 2 ]; then return 1; fi
    SERVICE_DETAIL+=" Check SSH, pg_isready, and database readiness."
    return 2
}

check_application_paths() {
    local ATTEMPT STATUS WEB_DETAIL
    WEB_API_STATE=error
    API_DB_STATE=error
    if ! probe_api_health "$API_IP" 127.0.0.1; then
        PORTS_DETAIL="Local API health failed; network rules cannot be assessed. $SERVICE_DETAIL"
        return 2
    fi
    if ! probe_postgres "$DB_IP" 127.0.0.1; then
        PORTS_DETAIL="Local database health failed; network rules cannot be assessed. $SERVICE_DETAIL"
        return 2
    fi
    if ! run_on_vm "$API_IP" 'command -v pg_isready >/dev/null'; then
        PORTS_DETAIL="Cannot run pg_isready on the API; check SSH and postgresql-client."
        return 2
    fi
    for ATTEMPT in {1..3}; do
        if probe_api_health "$WEB_IP" "$API_IP"; then
            WEB_API_STATE=resolved
        else
            STATUS=$?
            if [ "$STATUS" -eq 1 ]; then WEB_API_STATE=unresolved; else WEB_API_STATE=error; fi
        fi
        WEB_DETAIL="$SERVICE_DETAIL"
        if probe_postgres "$API_IP" "$DB_IP"; then
            API_DB_STATE=resolved
        else
            STATUS=$?
            if [ "$STATUS" -eq 1 ]; then API_DB_STATE=unresolved; else API_DB_STATE=error; fi
        fi
        PORTS_DETAIL="Web -> API: $WEB_DETAIL API -> database: $SERVICE_DETAIL"
        if [ "$WEB_API_STATE" = error ] || [ "$API_DB_STATE" = error ]; then return 2; fi
        if [ "$WEB_API_STATE" = resolved ] && [ "$API_DB_STATE" = resolved ]; then return 0; fi
        if [ "$ATTEMPT" -lt 3 ]; then sleep 2; fi
    done
    return 1
}

check_hardening() {
    local CONNECTION TRUSTED_IP CLIENT_PORT BASTION_PRIVATE SERVER_PORT POLICY STATUS
    local SOURCE TARGET PORT SCHEME
    if ! CONNECTION=$(run_on_vm "$BASTION_IP" 'printf "%s\n" "$SSH_CONNECTION"'); then
        HARDENING_DETAIL="Cannot determine the current SSH client address from the bastion."
        return 2
    fi
    read -r TRUSTED_IP CLIENT_PORT BASTION_PRIVATE SERVER_PORT <<< "$CONNECTION"
    if POLICY=$(python3 "$SCRIPT_DIR/sg-policy.py" --region "$REGION" --vpc-id "$VPC_ID" \
        --bastion "$BASTION_INSTANCE_ID" --web "$WEB_INSTANCE_ID" \
        --api "$API_INSTANCE_ID" --database "$DB_INSTANCE_ID" --trusted-ip "$TRUSTED_IP"); then
        :
    else
        STATUS=$?
        HARDENING_DETAIL="${POLICY:-Effective security-group policy could not be assessed; see stderr.}"
        if [ "$STATUS" -eq 1 ] && [ -n "$POLICY" ]; then return 1; else return 2; fi
    fi
    if check_application_paths; then :; else
        STATUS=$?
        HARDENING_DETAIL="Source policy passed, but application traffic is not healthy. Complete INC-4523 and preserve its fixes. $PORTS_DETAIL"
        return "$STATUS"
    fi
    for SCHEME in http https; do
        if curl -4 --noproxy '*' -kfsS --connect-timeout 5 --max-time 10 \
            "$SCHEME://$WEB_PUBLIC_IP/health" >/dev/null; then :; else
            STATUS=$?
            HARDENING_DETAIL="Required public web $SCHEME access failed (exit $STATUS)."
            case "$STATUS" in 7|28) return 1 ;; *) return 2 ;; esac
        fi
    done
    if run_on_vm "$BASTION_IP" "ping -4 -n -c 3 -W 2 $WEB_IP >/dev/null" 15; then :; else
        STATUS=$?
        HARDENING_DETAIL="Required bastion ICMP to the web server failed (exit $STATUS)."
        if [ "$STATUS" -eq 1 ]; then return 1; else return 2; fi
    fi
    for SOURCE in "$API_IP" "$DB_IP"; do
        if run_on_vm "$SOURCE" "ping -4 -n -c 1 -W 2 $WEB_IP >/dev/null" 10; then
            HARDENING_DETAIL="Unauthorized ICMP from $SOURCE to the web server still succeeds."
            return 1
        else
            STATUS=$?
        fi
        if [ "$STATUS" -ne 1 ]; then
            HARDENING_DETAIL="Negative ICMP check could not run (exit $STATUS)."
            return 2
        fi
    done
    # Unauthorized SSH to the web server's public IP from the validation client.
    if tcp_probe_local "$WEB_PUBLIC_IP" 22; then
        HARDENING_DETAIL="Unauthorized SSH to the web server's public IP still succeeds from the internet."
        return 1
    else
        STATUS=$?
    fi
    if [ "$STATUS" -ne 1 ]; then
        HARDENING_DETAIL="Negative public SSH check could not run (exit $STATUS)."
        return 2
    fi
    for POLICY in "$API_IP $WEB_IP 22" "$WEB_IP $API_IP 22" "$WEB_IP $DB_IP 22" \
        "$WEB_IP $BASTION_PRIVATE 22" "$BASTION_IP $DB_IP 5432"; do
        read -r SOURCE TARGET PORT <<< "$POLICY"
        if run_on_vm "$SOURCE" "nc -zw3 $TARGET $PORT" 10; then
            HARDENING_DETAIL="Unauthorized TCP from $SOURCE to $TARGET:$PORT still succeeds."
            return 1
        else
            STATUS=$?
        fi
        if [ "$STATUS" -ne 1 ]; then
            HARDENING_DETAIL="Negative TCP check could not run (exit $STATUS)."
            return 2
        fi
    done
    HARDENING_DETAIL="Effective security-group sources and live allowed/denied traffic passed (bastion SSH limited to the current client's public IPv4 /32)."
}
