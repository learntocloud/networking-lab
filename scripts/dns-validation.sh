#!/bin/bash

DNS_DETAIL=""

# run_on_vm is supplied by the provider's validation script.
dns_addresses_match() {
    local SOURCE_IP="$1"
    local EXPECTED_IP="$2"
    local LOOKUP="$3"
    local DESCRIPTION="${4:-DNS lookup from $SOURCE_IP}"
    local RESULT STATUS

    if RESULT=$(
        set -o pipefail
        run_on_vm "$SOURCE_IP" "
            set -o pipefail
            ADDRESSES=\$($LOOKUP | sort -u) &&
            [ \"\$ADDRESSES\" = \"$EXPECTED_IP\" ] &&
            printf resolved
        "
    ); then
        if [ "$RESULT" = "resolved" ]; then
            return 0
        fi
        DNS_DETAIL="$DESCRIPTION returned an invalid validation response."
        return 2
    else
        STATUS=$?
    fi

    # getent uses 2 for a missing name; dig uses 9 for no reply.
    if [ "$STATUS" -eq 1 ] || [ "$STATUS" -eq 2 ] ||
        [ "$STATUS" -eq 9 ] || [ "$STATUS" -eq 124 ]; then
        DNS_DETAIL="$DESCRIPTION did not resolve exclusively to $EXPECTED_IP (missing, incorrect, or timed out)."
        return 1
    fi

    DNS_DETAIL="$DESCRIPTION could not run (exit $STATUS); check SSH and diagnostic tools."
    return 2
}

validate_dns_hostname() {
    local HOSTNAME="$1"
    local EXPECTED_IP="$2"
    local DNS_SERVER="$3"
    shift 3
    local SOURCE_IP CLOUD_LOOKUP SYSTEM_LOOKUP
    local -a SOURCES=("$@")

    # Preserve lookup failures before filtering output.
    CLOUD_LOOKUP="ANSWER=\$(dig +time=3 +tries=1 +short @$DNS_SERVER $HOSTNAME A) &&
        printf \"%s\\n\" \"\$ANSWER\" | grep -E \"^[0-9]+(\\.[0-9]+){3}$\""
    SYSTEM_LOOKUP="ANSWER=\$(timeout 10 getent ahostsv4 $HOSTNAME) &&
        printf \"%s\\n\" \"\$ANSWER\" | cut -d \" \" -f1"

    # Keep the default scope for AWS/GCP callers.
    if [ "$#" -eq 0 ]; then
        SOURCES=("$WEB_IP" "$API_IP" "$DB_IP")
        dns_addresses_match "$WEB_IP" "$EXPECTED_IP" "$CLOUD_LOOKUP" \
            "Cloud DNS for $HOSTNAME on $WEB_IP" || return $?
    fi

    for SOURCE_IP in "${SOURCES[@]}"; do
        if [ -z "$SOURCE_IP" ]; then
            DNS_DETAIL="A DNS validation source IP is missing."
            return 2
        fi
        if [ "$#" -gt 0 ]; then
            dns_addresses_match "$SOURCE_IP" "$EXPECTED_IP" "$CLOUD_LOOKUP" \
                "Cloud DNS for $HOSTNAME on $SOURCE_IP" || return $?
        fi
        dns_addresses_match "$SOURCE_IP" "$EXPECTED_IP" "$SYSTEM_LOOKUP" \
            "System DNS for $HOSTNAME on $SOURCE_IP" || return $?
    done
}

# Returns 0 (resolved), 1 (DNS fault), or 2 (check error).
validate_private_dns() {
    local DNS_SERVER="$1"
    shift
    DNS_DETAIL=""

    if [ -z "$WEB_IP" ] || [ -z "$API_IP" ] || [ -z "$DB_IP" ]; then
        DNS_DETAIL="Expected service IPs are missing."
        return 2
    fi

    validate_dns_hostname web.internal.test "$WEB_IP" "$DNS_SERVER" "$@" &&
        validate_dns_hostname api.internal.test "$API_IP" "$DNS_SERVER" "$@" &&
        validate_dns_hostname db.internal.test "$DB_IP" "$DNS_SERVER" "$@" || return $?

    DNS_DETAIL="All service names resolve to the expected private IPs through cloud and system DNS on the checked VMs."
}
