#!/bin/sh
set -euf

if [ ! -d "build/edgeandnode/tap-escrow-manager" ]; then
  mkdir -p build/edgeandnode/tap-escrow-manager
  git clone git@github.com:edgeandnode/tap-escrow-manager build/edgeandnode/tap-escrow-manager --branch 'main'
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
dynamic_host_setup chain
dynamic_host_setup redpanda
dynamic_host_setup graph-node

until curl -s "http://${CONTROLLER_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done

echo "awaiting network subgraph"
export network_subgraph="$(curl "http://${CONTROLLER_HOST}:${CONTROLLER}/graph_subgraph")"
echo "network_subgraph=${network_subgraph}"

echo "awaiting escrow subgraph"
export escrow_subgraph="$(curl "http://${CONTROLLER_HOST}:${CONTROLLER}/escrow_subgraph")"
echo "escrow_subgraph=${escrow_subgraph}"

echo "awaiting graph_contracts"
graph_contracts="$(curl -s http://${CONTROLLER_HOST}:${CONTROLLER}/graph_contracts)"
token_contract="$(echo "${graph_contracts}" | jq -r '."1337".GraphToken.address')"

echo "awaiting scalar-tap-contracts"
tap_contracts="$(curl "http://${CONTROLLER_HOST}:${CONTROLLER}/scalar_tap_contracts")"
export escrow="$(echo "${tap_contracts}" | jq -r '.escrow')"
echo "escrow=${escrow}"

export GATEWAY_SENDER=${GATEWAY_SENDER_SECRET_KEY#0x}
echo "GATEWAY_SENDER=${GATEWAY_SENDER}"


export KAFKA_TOPIC="gateway_indexer_attempts"
export BOOTSTRAP_SERVERS="${REDPANDA_HOST}:${REDPANDA_KAFKA}"
rpk topic create $KAFKA_TOPIC --brokers=$BOOTSTRAP_SERVERS || true

# Fund the gateway with ETH and GRT
echo "Fund gateway with ETH"
cast send \
  --rpc-url="http://${CHAIN_HOST}:${CHAIN_RPC}" \
  --private-key="${ACCOUNT0_SECRET_KEY}" \
  "${GATEWAY_SENDER_ADDRESS}" \
  --value '1ether'
echo "Fund gateway with GRT"
cast send \
  --rpc-url="http://${CHAIN_HOST}:${CHAIN_RPC}" \
  --private-key="${ACCOUNT0_SECRET_KEY}" \
  "${token_contract}" \
  'transfer(address,uint256)' \
  "${GATEWAY_SENDER_ADDRESS}" \
  '1000000000000000000000000'
echo "Approve escrow contract to use GRT"
cast send \
  --rpc-url="http://${CHAIN_HOST}:${CHAIN_RPC}" \
  --private-key="${GATEWAY_SENDER_SECRET_KEY}" \
  "${token_contract}" \
  'approve(address,uint256)' \
  "${escrow}" \
  '1000000000000000000000000'

cd build/edgeandnode/tap-escrow-manager

envsubst <../../../tap-escrow-manager/config.jsonnet >config.jsonnet
jsonnet config.jsonnet >config.json
cat config.json

if [ ! -f "./tap-escrow-manager" ]; then
  cargo build -p tap-escrow-manager
  cp target/debug/tap-escrow-manager ./tap-escrow-manager
fi

export RUST_LOG=info,tap_escrow_manager=trace
./tap-escrow-manager config.json
