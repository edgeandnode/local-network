#!/bin/sh
set -eufx

if [ ! -d "build/semiotic-ai/timeline-aggregation-protocol" ]; then
  mkdir -p build/semiotic-ai/timeline-aggregation-protocol
  git clone git@github.com:semiotic-ai/timeline-aggregation-protocol build/semiotic-ai/timeline-aggregation-protocol --branch main
fi

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

until curl -s "http://${CONTROLLER_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done

echo "awaiting scalar-tap-contracts"
curl "http://${CONTROLLER_HOST}:${CONTROLLER}/scalar_tap_contracts" >scalar_tap_contracts.json

tap_verifier=$(cat scalar_tap_contracts.json | jq -r '."1337".TAPVerifier')
echo "tap_verifier=${tap_verifier}"


cd build/semiotic-ai/timeline-aggregation-protocol

export TAP_DOMAIN_NAME="TAP"
export TAP_DOMAIN_VERSION="1"
export TAP_DOMAIN_CHAIN_ID="1337"
export TAP_DOMAIN_VERIFYING_CONTRACT="${tap_verifier}"

export RUST_LOG=debug

ls -la

if [ ! -f "./tap-aggregator" ]; then
  cargo build -p tap_aggregator
  cp target/debug/tap_aggregator ./tap-aggregator
fi

./tap-aggregator \
  --private-key ${GATEWAY_SIGNER_SECRET_KEY} \
  --port ${TAP_AGGREGATOR}