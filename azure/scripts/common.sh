#!/bin/bash

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=10 -o ConnectionAttempts=1 -o BatchMode=yes
    -o ControlMaster=no -o ControlPath=none
    -o ServerAliveInterval=10 -o ServerAliveCountMax=3 -q)

PORTS_DETAIL=""
HARDENING_DETAIL=""

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
    RESOURCE_GROUP=$(get_terraform_output resource_group_name) || return 2
    DEPLOYMENT_ID=$(get_terraform_output deployment_id) || return 2
    BASTION_IP=$(get_terraform_output bastion_public_ip) || return 2
    API_IP=$(get_terraform_output api_server_private_ip) || return 2
    WEB_IP=$(get_terraform_output web_server_private_ip) || return 2
    WEB_PUBLIC_IP=$(get_terraform_output web_server_public_ip) || return 2
    DB_IP=$(get_terraform_output database_server_private_ip) || return 2
    SSH_KEY="$HOME/.ssh/netlab-key"

    if [ -z "$RESOURCE_GROUP" ] || [ -z "$DEPLOYMENT_ID" ] ||
        [ -z "$BASTION_IP" ] || [ -z "$API_IP" ] ||
        [ -z "$WEB_IP" ] || [ -z "$WEB_PUBLIC_IP" ] || [ -z "$DB_IP" ]; then
        echo "Error: Terraform outputs are incomplete. Finish setup first." >&2
        return 2
    fi
}

run_on_vm() {
    local TARGET_IP="$1"
    local COMMAND PROXY
    local -a HOP=()
    printf -v COMMAND '%q' "$2"

    if [ "$TARGET_IP" != "$BASTION_IP" ]; then
        printf -v PROXY '%q ' ssh "${SSH_OPTS[@]}" -i "$SSH_KEY" \
            -W '%h:%p' labadmin@"$BASTION_IP"
        HOP=(-o "ProxyCommand=$PROXY")
    fi

    ssh -n "${SSH_OPTS[@]}" -i "$SSH_KEY" "${HOP[@]}" labadmin@"$TARGET_IP" \
        "timeout ${3:-60} bash -o pipefail -c $COMMAND"
}

check_vm_tools() {
    run_on_vm "$1" '
        for TOOL in curl python3 nc dig getent timeout jq sort grep cut ping; do
            if ! command -v "$TOOL" >/dev/null; then
                echo "Error: Required diagnostic tool $TOOL is missing." >&2
                exit 127
            fi
        done
    '
}

# Checks return 0 (pass), 1 (unresolved), or 2 (error).
probe_api_https() {
    local STATUS CODE
    if STATUS=$(run_on_vm "$API_IP" \
        'curl -4 --noproxy "*" -sS -f -L --max-redirs 3 --connect-timeout 5 --max-time 10 --retry 2 --retry-all-errors --retry-delay 2 --retry-max-time 35 -o /dev/null -w "%{http_code}" https://example.com' 50); then
        if [[ "$STATUS" == 2[0-9][0-9] ]]; then
            return 0
        fi
        EGRESS_DETAIL="The external HTTPS endpoint returned unexpected HTTP status $STATUS."
        return 2
    else
        CODE=$?
    fi

    case "$CODE" in
        7|28)
            EGRESS_DETAIL="The API cannot connect to the external HTTPS endpoint (curl exit $CODE)."
            return 1
            ;;
        *)
            EGRESS_DETAIL="Could not verify API HTTPS connectivity (exit $CODE); check SSH, curl, public DNS, TLS, and the external endpoint."
            return 2
            ;;
    esac
}

check_api_egress() {
    local SUBNET_ID SUBNET NAT_ID NAT PUBLIC_IDS PREFIX_IDS ID ADDRESS
    local NETWORKS="" OUTBOUND_IP MATCH_COMMAND CODE
    EGRESS_DETAIL=""

    if ! check_vm_tools "$API_IP"; then
        EGRESS_DETAIL="Cannot reach the API over SSH or required diagnostic tools are missing."
        return 2
    fi
    if ! SUBNET_ID=$(az network nic show -g "$RESOURCE_GROUP" \
        -n "nic-api-$DEPLOYMENT_ID" --query 'ipConfigurations[0].subnet.id' -o tsv) ||
        [ -z "$SUBNET_ID" ]; then
        EGRESS_DETAIL="Cannot read the API network interface from Azure."
        return 2
    fi
    if ! SUBNET=$(az network vnet subnet show --ids "$SUBNET_ID" -o json) ||
        ! NAT_ID=$(jq -r '.natGateway.id // ""' <<< "$SUBNET"); then
        EGRESS_DETAIL="Cannot read the API subnet from Azure."
        return 2
    fi
    if [ -z "$NAT_ID" ]; then
        EGRESS_DETAIL="The API subnet has no NAT gateway association."
        return 1
    fi
    if ! NAT=$(az network nat gateway show --ids "$NAT_ID" -o json) ||
        ! PUBLIC_IDS=$(jq -r '.publicIpAddresses[]?.id' <<< "$NAT") ||
        ! PREFIX_IDS=$(jq -r '.publicIpPrefixes[]?.id' <<< "$NAT"); then
        EGRESS_DETAIL="Cannot read the associated NAT gateway from Azure."
        return 2
    fi

    while IFS= read -r ID; do
        [ -n "$ID" ] || continue
        if ! ADDRESS=$(az network public-ip show --ids "$ID" --query ipAddress -o tsv); then
            EGRESS_DETAIL="Cannot read a NAT public IP from Azure."
            return 2
        fi
        [ -z "$ADDRESS" ] || NETWORKS+="$ADDRESS "
    done <<< "$PUBLIC_IDS"
    while IFS= read -r ID; do
        [ -n "$ID" ] || continue
        if ! ADDRESS=$(az network public-ip prefix show --ids "$ID" --query ipPrefix -o tsv); then
            EGRESS_DETAIL="Cannot read a NAT public IP prefix from Azure."
            return 2
        fi
        [ -z "$ADDRESS" ] || NETWORKS+="$ADDRESS "
    done <<< "$PREFIX_IDS"
    if [ -z "$NETWORKS" ]; then
        EGRESS_DETAIL="The associated NAT gateway has no allocated public IPs."
        return 1
    fi

    if probe_api_https; then
        :
    else
        return $?
    fi
    if ! OUTBOUND_IP=$(run_on_vm "$API_IP" \
        'curl -4 --noproxy "*" -fsS --connect-timeout 5 --max-time 10 --retry 2 --retry-all-errors --retry-delay 2 --retry-max-time 35 https://api.ipify.org' 50); then
        EGRESS_DETAIL="Could not obtain the API outbound IP from api.ipify.org; NAT egress could not be verified."
        return 2
    fi

    printf -v MATCH_COMMAND 'python3 -c %q %q %q' \
        'import ipaddress, sys
try:
    address = ipaddress.ip_address(sys.argv[1])
    networks = [ipaddress.ip_network(value) for value in sys.argv[2].split()]
except ValueError as error:
    print(error, file=sys.stderr)
    sys.exit(2)
sys.exit(0 if any(address in network for network in networks) else 1)' \
        "$OUTBOUND_IP" "$NETWORKS"
    if run_on_vm "$API_IP" "$MATCH_COMMAND"; then
        EGRESS_DETAIL="External HTTPS works and outbound IP $OUTBOUND_IP belongs to the associated NAT gateway."
        return 0
    else
        CODE=$?
    fi
    if [ "$CODE" -eq 1 ]; then
        EGRESS_DETAIL="Outbound IP $OUTBOUND_IP does not belong to the API subnet's NAT gateway."
        return 1
    fi
    EGRESS_DETAIL="Could not compare the observed outbound IP with the NAT public IPs (exit $CODE)."
    return 2
}

probe_api_health() {
    local SOURCE_IP="$1" TARGET_IP="$2" RESPONSE STATUS
    if RESPONSE=$(run_on_vm "$SOURCE_IP" \
        "curl --noproxy '*' -fsS --connect-timeout 3 --max-time 5 http://$TARGET_IP:8080/health" 15); then
        if jq -se 'length == 1 and (.[0] | type == "object" and .status == "healthy")' \
            <<< "$RESPONSE" >/dev/null 2>&1; then
            SERVICE_DETAIL="The API health endpoint on $TARGET_IP:8080 is healthy."
            return 0
        fi
        SERVICE_DETAIL="The endpoint on $TARGET_IP:8080 did not return healthy API JSON."
        return 2
    else
        STATUS=$?
    fi
    if [ "$STATUS" -eq 7 ] || [ "$STATUS" -eq 28 ]; then
        SERVICE_DETAIL="$SOURCE_IP cannot reach the API on $TARGET_IP:8080 (curl exit $STATUS)."
        return 1
    fi
    SERVICE_DETAIL="Could not verify API health from $SOURCE_IP on $TARGET_IP:8080 (exit $STATUS); check SSH, tools, and the service."
    return 2
}

probe_postgres() {
    local SOURCE_IP="$1" TARGET_IP="$2" STATUS
    if run_on_vm "$SOURCE_IP" \
        "pg_isready -q -h $TARGET_IP -p 5432 -U labuser -d labdb -t 3" 15; then
        SERVICE_DETAIL="PostgreSQL on $TARGET_IP:5432 is accepting connections."
        return 0
    else
        STATUS=$?
    fi
    if [ "$STATUS" -eq 2 ]; then
        SERVICE_DETAIL="$SOURCE_IP received no PostgreSQL response from $TARGET_IP:5432."
        return 1
    fi
    if [ "$STATUS" -eq 1 ]; then
        SERVICE_DETAIL="PostgreSQL on $TARGET_IP:5432 is rejecting connections; check database readiness."
    else
        SERVICE_DETAIL="Could not check PostgreSQL from $SOURCE_IP on $TARGET_IP:5432 (exit $STATUS); check SSH and pg_isready."
    fi
    return 2
}

check_application_paths() {
    local ATTEMPT STATUS WEB_DETAIL DB_DETAIL
    WEB_API_STATE=error
    API_DB_STATE=error
    PORTS_DETAIL=""

    if ! probe_api_health "$API_IP" 127.0.0.1; then
        PORTS_DETAIL="Local API health failed; network rules cannot be assessed. $SERVICE_DETAIL"
        return 2
    fi
    if ! probe_postgres "$DB_IP" 127.0.0.1; then
        PORTS_DETAIL="Local database health failed; network rules cannot be assessed. $SERVICE_DETAIL"
        return 2
    fi
    if ! run_on_vm "$API_IP" 'command -v pg_isready >/dev/null'; then
        PORTS_DETAIL="Cannot run pg_isready on the API VM; check SSH and finish setup to install postgresql-client."
        return 2
    fi

    for ATTEMPT in {1..3}; do
        if probe_api_health "$WEB_IP" "$API_IP"; then
            WEB_API_STATE=resolved
        else
            STATUS=$?
            if [ "$STATUS" -eq 1 ]; then
                WEB_API_STATE=unresolved
            else
                WEB_API_STATE=error
            fi
        fi
        WEB_DETAIL="$SERVICE_DETAIL"

        if probe_postgres "$API_IP" "$DB_IP"; then
            API_DB_STATE=resolved
        else
            STATUS=$?
            if [ "$STATUS" -eq 1 ]; then
                API_DB_STATE=unresolved
            else
                API_DB_STATE=error
            fi
        fi
        DB_DETAIL="$SERVICE_DETAIL"
        PORTS_DETAIL="Web -> API: $WEB_DETAIL API -> database: $DB_DETAIL"

        if [ "$WEB_API_STATE" = error ] || [ "$API_DB_STATE" = error ]; then
            return 2
        fi
        if [ "$WEB_API_STATE" = resolved ] && [ "$API_DB_STATE" = resolved ]; then
            return 0
        fi
        if [ "$ATTEMPT" -lt 3 ]; then
            sleep 2
        fi
    done
    return 1
}

check_hardening() {
    local CONNECTION TRUSTED_IP CLIENT_PORT BASTION_PRIVATE SERVER_PORT POLICY STATUS
    local SOURCE TARGET PORT ATTEMPT RESULT SCHEME
    if ! CONNECTION=$(run_on_vm "$BASTION_IP" 'printf "%s\n" "$SSH_CONNECTION"'); then
        HARDENING_DETAIL="Cannot determine the current SSH client address from the bastion."
        return 2
    fi
    read -r TRUSTED_IP CLIENT_PORT BASTION_PRIVATE SERVER_PORT <<< "$CONNECTION"
    if POLICY=$(python3 "$SCRIPT_DIR/nsg-policy.py" --resource-group "$RESOURCE_GROUP" \
        --deployment-id "$DEPLOYMENT_ID" --trusted-ip "$TRUSTED_IP"); then
        :
    else
        STATUS=$?
        HARDENING_DETAIL="${POLICY:-Effective NSG policy could not be assessed; see the error above.}"
        if [ "$STATUS" -eq 1 ] && [ -n "$POLICY" ]; then return 1; else return 2; fi
    fi

    if check_application_paths; then
        :
    else
        STATUS=$?
        HARDENING_DETAIL="Source restrictions passed, but application traffic is not healthy. Complete INC-4523 and preserve its fixes. $PORTS_DETAIL"
        return "$STATUS"
    fi
    if run_on_vm "$BASTION_IP" \
        "curl --noproxy '*' -fsS --max-time 5 http://$WEB_IP/health && curl --noproxy '*' -kfsS --max-time 5 https://$WEB_IP/health" >/dev/null; then
        :
    else
        STATUS=$?
        HARDENING_DETAIL="Permitted web HTTP/HTTPS access from the bastion failed (exit $STATUS)."
        case "$STATUS" in
            7|28) return 1 ;;
            *) return 2 ;;
        esac
    fi
    for SCHEME in http https; do
        if curl -4 --noproxy '*' -kfsS --connect-timeout 5 --max-time 10 \
            "$SCHEME://$WEB_PUBLIC_IP/health" >/dev/null; then
            :
        else
            STATUS=$?
            HARDENING_DETAIL="Public web $SCHEME access failed (curl exit $STATUS); preserve HTTP/HTTPS access."
            case "$STATUS" in
                7|28) return 1 ;;
                *) return 2 ;;
            esac
        fi
    done

    for ATTEMPT in {1..3}; do
        if run_on_vm "$BASTION_IP" "ping -4 -n -c 1 -W 2 $WEB_IP >/dev/null" 10; then
            RESULT=0
            break
        else
            RESULT=$?
        fi
        if [ "$RESULT" -ne 1 ]; then
            HARDENING_DETAIL="The permitted bastion-to-web ICMP check could not run (exit $RESULT)."
            return 2
        fi
        sleep 2
    done
    if [ "$RESULT" -ne 0 ]; then
        HARDENING_DETAIL="Bastion-to-web ICMP must remain reachable."
        return 1
    fi

    for SOURCE in "$API_IP" "$DB_IP"; do
        if run_on_vm "$SOURCE" "ping -4 -n -c 1 -W 2 $WEB_IP >/dev/null" 10; then
            HARDENING_DETAIL="Unauthorized ICMP from $SOURCE to the web VM still succeeds."
            return 1
        else
            STATUS=$?
        fi
        if [ "$STATUS" -ne 1 ]; then
            HARDENING_DETAIL="The negative ICMP check on $SOURCE could not run (exit $STATUS)."
            return 2
        fi
    done

    for POLICY in "$API_IP $WEB_IP 22" "$WEB_IP $API_IP 22" "$WEB_IP $DB_IP 22" \
        "$WEB_IP $BASTION_PRIVATE 22" "$BASTION_PRIVATE $DB_IP 5432"; do
        read -r SOURCE TARGET PORT <<< "$POLICY"
        if [ "$SOURCE" = "$BASTION_PRIVATE" ]; then SOURCE="$BASTION_IP"; fi
        if run_on_vm "$SOURCE" "nc -zw3 $TARGET $PORT" 10; then
            HARDENING_DETAIL="Unauthorized TCP access from $SOURCE to $TARGET:$PORT still succeeds."
            return 1
        else
            STATUS=$?
        fi
        if [ "$STATUS" -ne 1 ]; then
            HARDENING_DETAIL="The negative TCP check on $SOURCE could not run (exit $STATUS)."
            return 2
        fi
    done
    HARDENING_DETAIL="Effective source restrictions and live allowed/denied traffic checks passed (trusted SSH source $TRUSTED_IP/32)."
}
