#!/bin/sh
set -euf

if [ ! -d "build/edgeandnode/graph-gateway" ]; then
  mkdir -p build/edgeandnode/graph-gateway
  git clone git@github.com:edgeandnode/graph-gateway build/edgeandnode/graph-gateway --branch 'main'
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
dynamic_host_setup graph-node
dynamic_host_setup chain
dynamic_host_setup ipfs
dynamic_host_setup redpanda
dynamic_host_setup studio-admin

echo "awaiting graph_subgraph"
until curl -s "http://${CONTROLLER_HOST}:${CONTROLLER}/graph_subgraph" >/dev/null; do sleep 1; done
echo "awaiting allocation_subgraph"
until curl -s "http://${CONTROLLER_HOST}:${CONTROLLER}/allocation_subgraph" >/dev/null; do sleep 1; done
echo "awaiting block_oracle"
until curl -s "http://${CONTROLLER_HOST}:${CONTROLLER}/block_oracle_subgraph" >/dev/null; do sleep 1; done

cd build/edgeandnode/graph-gateway

echo "awaiting graph_contracts"
dispute_manager="$(curl "http://${CONTROLLER_HOST}:${CONTROLLER}/graph_contracts" | jq -r '."1337".DisputeManager.address')"
echo "dispute_manager=${dispute_manager}"
export DISPUTE_MANAGER="${dispute_manager}"

echo "awaiting scalar-tap-contracts"
curl "http://${CONTROLLER_HOST}:${CONTROLLER}/scalar_tap_contracts" >scalar_tap_contracts.json
escrow=$(cat scalar_tap_contracts.json | jq -r '.escrow')
echo "escrow=${escrow}"
tap_verifier=$(cat scalar_tap_contracts.json | jq -r '.tap_verifier')
echo "tap_verifier=${tap_verifier}"
export TAP_VERIFIER="${tap_verifier}"

echo "awaiting studio_admin_auth"
studio_admin_auth="$(curl "http://${CONTROLLER_HOST}:${CONTROLLER}/studio_admin_auth")"
echo "studio_admin_auth=${studio_admin_auth}"
export STUDIO_AUTH="${studio_admin_auth}"

export GATEWAY_SIGNER=${GATEWAY_SIGNER_SECRET_KEY}
echo "GATEWAY_SIGNER=${GATEWAY_SIGNER}"

envsubst <../../../gateway/config.jsonnet >config.jsonnet
jsonnet config.jsonnet >config.json
export RUST_LOG=info,graph_gateway=trace,gateway_framework=trace,gateway_framework::chains::ethereum::json_rpc=info
if cargo --list | grep watch; then
  cargo watch -x 'run --bin graph-gateway config.json'
else
  cargo run --bin graph-gateway config.json
fi
