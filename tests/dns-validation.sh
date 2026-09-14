#!/bin/bash
set -euo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TRACE="$(mktemp)"
export TEST_TRACE
trap 'rm -f "$TEST_TRACE"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

record_ip() {
    case "$1" in
        web.internal.test) printf '%s' "$WEB_IP" ;;
        api.internal.test) printf '%s' "$API_IP" ;;
        db.internal.test) printf '%s' "$DB_IP" ;;
        *) return 2 ;;
    esac
}

# Execute both SSH hops locally to exercise the real provider quoting/encoding.
ssh() {
    local TARGET=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -o|-i) shift 2 ;;
            -*) shift ;;
            *@*) TARGET="${1#*@}"; shift; break ;;
            *) return 2 ;;
        esac
    done

    if [ "$TARGET" != "$BASTION_IP" ]; then
        case "$TARGET" in
            "$WEB_IP"|"$API_IP"|"$DB_IP") ;;
            *) return 2 ;;
        esac
        export TEST_SOURCE_IP="$TARGET"
        case "$TEST_SCENARIO" in
            ssh-failure) return 255 ;;
            ssh-partial-failure) printf resolved; return 255 ;;
        esac
    fi

    bash -c "$*"
}

getent() {
    [ "$1" = ahostsv4 ] || return 2
    local IP MODE=success
    IP=$(record_ip "$2") || return 2
    printf 'system %s %s\n' "$TEST_SOURCE_IP" "$2" >> "$TEST_TRACE"
    if [ "$TEST_SOURCE_IP" = "$TEST_FAIL_SOURCE" ] && [ "$2" = "$TEST_FAIL_HOST" ]; then
        MODE="$TEST_SCENARIO"
    fi
    case "$MODE" in
        system-failure) return 2 ;;
        system-wrong) IP=10.0.9.99 ;;
        system-extra) printf '10.0.9.99 STREAM %s\n' "$2" ;;
        system-command-failure) printf '%s STREAM %s\n' "$IP" "$2"; return 2 ;;
    esac
    printf '%s   STREAM %s\n%s   DGRAM\n%s   RAW\n' "$IP" "$2" "$IP" "$IP"
}

dig() {
    local HOSTNAME="$5" IP MODE=success
    [ "$*" = "+time=3 +tries=1 +short @$TEST_DNS_SERVER $HOSTNAME A" ] || return 2
    [ "$TEST_SOURCE_IP" = "$WEB_IP" ] || return 2
    IP=$(record_ip "$HOSTNAME") || return 2
    printf 'cloud %s %s\n' "$TEST_SOURCE_IP" "$HOSTNAME" >> "$TEST_TRACE"
    if [ "$HOSTNAME" = "$TEST_FAIL_HOST" ]; then
        MODE="$TEST_SCENARIO"
    fi
    case "$MODE" in
        cloud-missing) return 0 ;;
        cloud-wrong) IP=10.0.9.99 ;;
        cloud-extra) printf '10.0.9.99\n' ;;
        cloud-servfail) printf ';; Got SERVFAIL reply\n'; return 0 ;;
        cloud-timeout) return 9 ;;
        cloud-command-failure) printf '%s\n' "$IP"; return 9 ;;
        cloud-cname) printf 'alias.internal.test.\n' ;;
        cloud-cname-missing) printf 'alias.internal.test.\n'; return 0 ;;
    esac
    printf '%s\n' "$IP"
}

timeout() {
    [ "$1" = 10 ] || return 2
    shift
    if [ "$TEST_SCENARIO" = system-timeout ]; then
        return 124
    fi
    "$@"
}

export -f ssh getent dig timeout record_ip

run_provider_cases() (
    local PROVIDER="$1" SCENARIO EXPECTED ACTUAL SOURCE HOSTNAME COUNT=0
    source "$TEST_ROOT/$PROVIDER/scripts/validate.sh"
    case "$PROVIDER" in
        azure) TEST_DNS_SERVER=168.63.129.16 ;;
        aws) TEST_DNS_SERVER=169.254.169.253 ;;
        gcp) TEST_DNS_SERVER=169.254.169.254 ;;
    esac
    export TEST_DNS_SERVER ADMIN_USERNAME=labadmin SSH_KEY=/unused
    export BASTION_IP=192.0.2.10

    for SCENARIO in success system-failure cloud-missing system-wrong cloud-wrong \
        system-extra cloud-extra cloud-servfail system-command-failure \
        cloud-command-failure system-timeout cloud-timeout ssh-failure \
        ssh-partial-failure api-resolver-failure db-resolver-failure \
        missing-web-ip missing-api-ip missing-db-ip missing-web-record missing-api-record \
        cloud-cname cloud-cname-missing; do
        export WEB_IP=10.0.2.4 API_IP=10.0.2.5 DB_IP=10.0.3.4
        export TEST_SCENARIO="$SCENARIO" TEST_FAIL_SOURCE="$WEB_IP" TEST_FAIL_HOST=db.internal.test
        EXPECTED=unresolved
        case "$SCENARIO" in
            success|cloud-cname) EXPECTED=resolved ;;
            api-resolver-failure) TEST_SCENARIO=system-failure; TEST_FAIL_SOURCE="$API_IP" ;;
            db-resolver-failure) TEST_SCENARIO=system-failure; TEST_FAIL_SOURCE="$DB_IP" ;;
            missing-web-ip) WEB_IP="" ;;
            missing-api-ip) API_IP="" ;;
            missing-db-ip) DB_IP="" ;;
            missing-web-record) TEST_SCENARIO=cloud-missing; TEST_FAIL_HOST=web.internal.test ;;
            missing-api-record) TEST_SCENARIO=cloud-missing; TEST_FAIL_HOST=api.internal.test ;;
        esac
        : > "$TEST_TRACE"

        validate_inc_4522
        if [ "$PROVIDER" = azure ]; then
            ACTUAL="${INCIDENTS[INC-4522]}"
        else
            ACTUAL="$INC_4522"
        fi
        [ "$ACTUAL" = "$EXPECTED" ] || fail "$PROVIDER/$SCENARIO: expected $EXPECTED, got $ACTUAL"

        if [ "$EXPECTED" = resolved ]; then
            [ "$(wc -l < "$TEST_TRACE")" -eq 12 ] || fail "$PROVIDER: expected 12 lookups"
            for HOSTNAME in web.internal.test api.internal.test db.internal.test; do
                grep -Fx "cloud $WEB_IP $HOSTNAME" "$TEST_TRACE" >/dev/null ||
                    fail "$PROVIDER: missing cloud lookup for $HOSTNAME"
                for SOURCE in "$WEB_IP" "$API_IP" "$DB_IP"; do
                    grep -Fx "system $SOURCE $HOSTNAME" "$TEST_TRACE" >/dev/null ||
                        fail "$PROVIDER: missing system lookup for $HOSTNAME on $SOURCE"
                done
            done
        fi
        case "$SCENARIO" in
            missing-*-ip) [ ! -s "$TEST_TRACE" ] || fail "$PROVIDER: queried DNS with missing VM IPs" ;;
        esac
        COUNT=$((COUNT + 1))
    done

    # A later successful run must clear a previous unresolved result.
    export TEST_SCENARIO=success
    validate_inc_4522
    if [ "$PROVIDER" = azure ]; then
        [ "${INCIDENTS[INC-4522]}" = resolved ] || fail "$PROVIDER: recovery failed"
    else
        [ "$INC_4522" = resolved ] || fail "$PROVIDER: recovery failed"
    fi
    printf '%s: %s scenarios and recovery passed\n' "$PROVIDER" "$COUNT"
)

for PROVIDER in azure aws gcp; do
    run_provider_cases "$PROVIDER"
    bash "$TEST_ROOT/$PROVIDER/scripts/validate.sh" --help >/dev/null
    if grep -R -n -E 'internal[.-]local' "$TEST_ROOT/$PROVIDER/terraform" "$TEST_ROOT/$PROVIDER/scripts" \
        --include='*.tf' --include='*.sh'; then
        fail "$PROVIDER: legacy DNS namespace remains in executable configuration"
    fi
done
