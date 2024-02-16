#!/bin/sh
set -euf

. ./.env

dynamic_host_setup() {
    if [ $# -eq 0 ]; then
        echo "No name provided."
        return 1
    fi

    # Convert the name to uppercase for the variable name
    local name_upper=$(echo $1 | tr '-' '_' | tr '[:lower:]' '[:upper:]')
    local export_name="${name_upper}_HOST"
    local host_name="$1"

    # Directly use 'eval' for dynamic variable assignment to avoid bad substitution
    eval export ${export_name}="${host_name}"
    if ! getent hosts "${host_name}" >/dev/null; then
        eval export ${export_name}="\$DOCKER_GATEWAY_HOST"
    fi

    # Use 'eval' for echoing dynamic variable value
    eval echo "${export_name} is set to \$${export_name}"
}

dynamic_host_setup controller
dynamic_host_setup chain

until curl -s "http://${CONTROLLER_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done

echo "awaiting scalar-tap-contracts"
tap_contracts="$(curl "http://${CONTROLLER_HOST}:${CONTROLLER}/scalar_tap_contracts")"
export escrow="$(echo "${tap_contracts}" | jq -r '.escrow')"
echo "escrow=${escrow}"

response=$(curl -s --max-time 1 "http://${CONTROLLER_HOST}:${CONTROLLER}/tap_contract_calls" || true)
if [ ! -n "$response" ]; then
    python contract-calls.py "$escrow"
    curl "http://${CONTROLLER_HOST}:${CONTROLLER}/escrow_subgraph" -d "true"
else
    echo "tap_contract_calls already exists"
fi


