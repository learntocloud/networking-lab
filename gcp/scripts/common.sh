#!/bin/bash

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=10 -o ConnectionAttempts=1 -o BatchMode=yes
    -o ControlMaster=no -o ControlPath=none
    -o ServerAliveInterval=10 -o ServerAliveCountMax=3 -q)

EGRESS_DETAIL=""
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
    PROJECT_ID=$(get_terraform_output project_id) || return 2
    DEPLOYMENT_ID=$(get_terraform_output deployment_id) || return 2
    REGION=$(get_terraform_output region) || return 2
    ZONE=$(get_terraform_output zone) || return 2
    ADMIN_USERNAME=$(get_terraform_output admin_username) || return 2
    BASTION_IP=$(get_terraform_output bastion_public_ip) || return 2
    WEB_IP=$(get_terraform_output web_server_private_ip) || return 2
    WEB_PUBLIC_IP=$(get_terraform_output web_server_public_ip) || return 2
    API_IP=$(get_terraform_output api_server_private_ip) || return 2
    DB_IP=$(get_terraform_output database_server_private_ip) || return 2
    SSH_KEY="$HOME/.ssh/netlab-key"
    if [ -z "$PROJECT_ID" ] || [ -z "$DEPLOYMENT_ID" ] || [ -z "$REGION" ] ||
        [ -z "$ZONE" ] || [ -z "$ADMIN_USERNAME" ] || [ -z "$BASTION_IP" ] ||
        [ -z "$WEB_IP" ] || [ -z "$WEB_PUBLIC_IP" ] || [ -z "$API_IP" ] || [ -z "$DB_IP" ]; then
        echo "Error: Terraform outputs are incomplete. Finish setup first." >&2
        return 2
    fi
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

# Checks return 0 (pass), 1 (unresolved), or 2 (execution/service error).
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

check_api_egress() {
    local INSTANCE MAPPINGS NAT_IPS OUTBOUND_IP
    if ! check_vm_tools "$API_IP"; then
        EGRESS_DETAIL="Cannot reach the API over SSH or diagnostic tools are missing."
        return 2
    fi
    if ! INSTANCE=$(gcloud compute instances describe "vm-api-$DEPLOYMENT_ID" \
        --project "$PROJECT_ID" --zone "$ZONE" --format=json); then
        EGRESS_DETAIL="Cannot read the API instance from GCP."
        return 2
    fi
    if ! jq -e '.networkInterfaces | length == 1' <<< "$INSTANCE" >/dev/null; then
        EGRESS_DETAIL="Only the lab single-interface topology is supported."
        return 2
    fi
    if jq -e '.networkInterfaces[0].accessConfigs | length > 0' <<< "$INSTANCE" >/dev/null; then
        EGRESS_DETAIL="The API must stay private; a public IP is not a Cloud NAT repair."
        return 1
    fi
    if ! MAPPINGS=$(gcloud compute routers get-nat-mapping-info "router-$DEPLOYMENT_ID" \
        --project "$PROJECT_ID" --region "$REGION" --format=json) ||
        ! NAT_IPS=$(jq -er --arg ip "$API_IP" --arg instance "vm-api-$DEPLOYMENT_ID" '
            if type != "array" then error("Invalid NAT mapping response") else
            [.[] | select(.instanceName == $instance) | .interfaceNatMappings[] |
             select(.sourceVirtualIp == $ip and (.sourceAliasIpRange // "") == "") |
             .natIpPortRanges[]? | split(":")[0]] | unique | join(" ") end
        ' <<< "$MAPPINGS"); then
        EGRESS_DETAIL="Cannot read Cloud NAT mappings for the API."
        return 2
    fi
    if [ -z "$NAT_IPS" ]; then
        EGRESS_DETAIL="The API interface has no Cloud NAT mapping on the lab router."
        return 1
    fi
    probe_api_https || return $?
    if ! OUTBOUND_IP=$(run_on_vm "$API_IP" \
        'curl -4 --noproxy "*" -fsS --connect-timeout 5 --max-time 10 --retry 2 --retry-all-errors --retry-delay 2 --retry-max-time 35 https://api.ipify.org' 50); then
        EGRESS_DETAIL="Could not obtain the API outbound IP from api.ipify.org."
        return 2
    fi
    if [[ " $NAT_IPS " != *" $OUTBOUND_IP "* ]] || [ -z "$OUTBOUND_IP" ]; then
        EGRESS_DETAIL="Observed outbound IP $OUTBOUND_IP is not in the API's Cloud NAT mappings."
        return 1
    fi
    EGRESS_DETAIL="External HTTPS works through Cloud NAT (outbound IP $OUTBOUND_IP)."
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
    if ! probe_api_health "$API_IP" 127.0.0.1 ||
        ! probe_postgres "$DB_IP" 127.0.0.1; then
        PORTS_DETAIL="Local service health failed; network rules cannot be assessed. $SERVICE_DETAIL"
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
    if POLICY=$(python3 "$SCRIPT_DIR/firewall-policy.py" --project "$PROJECT_ID" \
        --zone "$ZONE" --deployment-id "$DEPLOYMENT_ID" --trusted-ip "$TRUSTED_IP"); then
        :
    else
        STATUS=$?
        HARDENING_DETAIL="${POLICY:-Effective firewall policy could not be assessed; see stderr.}"
        if [ "$STATUS" -eq 1 ] && [ -n "$POLICY" ]; then return 1; else return 2; fi
    fi
    if check_application_paths; then :; else
        STATUS=$?
        HARDENING_DETAIL="Source policy passed, but application traffic is not healthy. Complete INC-4523. $PORTS_DETAIL"
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
    for TARGET in "$WEB_IP" "$API_IP" "$DB_IP"; do
        if run_on_vm "$BASTION_IP" "ping -4 -n -c 3 -W 2 $TARGET >/dev/null" 15; then :; else
            STATUS=$?
            HARDENING_DETAIL="Required bastion ICMP to $TARGET failed (exit $STATUS)."
            if [ "$STATUS" -eq 1 ]; then return 1; else return 2; fi
        fi
    done
    for SOURCE in "$API_IP" "$DB_IP"; do
        if run_on_vm "$SOURCE" "ping -4 -n -c 1 -W 2 $WEB_IP >/dev/null" 10; then
            HARDENING_DETAIL="Unauthorized ICMP from $SOURCE to web still succeeds."
            return 1
        else
            STATUS=$?
        fi
        if [ "$STATUS" -ne 1 ]; then
            HARDENING_DETAIL="Negative ICMP check could not run (exit $STATUS)."
            return 2
        fi
    done
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
    HARDENING_DETAIL="Effective source restrictions and live allowed/denied traffic passed (bastion SSH limited to the current client's public IPv4 /32)."
}
