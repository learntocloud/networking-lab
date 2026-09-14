#!/bin/bash

# run_on_vm is supplied by the provider's validation script.
dns_addresses_match() {
    local SOURCE_IP="$1"
    local EXPECTED_IP="$2"
    local LOOKUP="$3"
    local RESULT

    if ! RESULT=$(
        set -o pipefail
        run_on_vm "$SOURCE_IP" "
            set -o pipefail
            ADDRESSES=\$($LOOKUP | sort -u) &&
            [ \"\$ADDRESSES\" = \"$EXPECTED_IP\" ] &&
            printf resolved
        "
    ); then
        return 1
    fi

    [ "$RESULT" = "resolved" ]
}

validate_dns_hostname() {
    local HOSTNAME="$1"
    local EXPECTED_IP="$2"
    local DNS_SERVER="$3"
    local SOURCE_IP

    # Check cloud DNS independently so /etc/hosts alone cannot satisfy the incident.
    if ! dns_addresses_match "$WEB_IP" "$EXPECTED_IP" \
        "dig +time=3 +tries=1 +short @$DNS_SERVER $HOSTNAME A | grep -E \"^[0-9]+(\\.[0-9]+){3}$\""; then
        return 1
    fi

    for SOURCE_IP in "$WEB_IP" "$API_IP" "$DB_IP"; do
        if ! dns_addresses_match "$SOURCE_IP" "$EXPECTED_IP" \
            "timeout 10 getent ahostsv4 $HOSTNAME | cut -d \" \" -f1"; then
            return 1
        fi
    done
}

validate_private_dns() {
    local DNS_SERVER="$1"

    if [ -z "$WEB_IP" ] || [ -z "$API_IP" ] || [ -z "$DB_IP" ]; then
        return 1
    fi

    validate_dns_hostname web.internal.test "$WEB_IP" "$DNS_SERVER" &&
        validate_dns_hostname api.internal.test "$API_IP" "$DNS_SERVER" &&
        validate_dns_hostname db.internal.test "$DB_IP" "$DNS_SERVER"
}
