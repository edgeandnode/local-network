#!/bin/sh
set -euf

if [ ! -d "build/edgeandnode/tap-escrow-manager" ]; then
  mkdir -p build/edgeandnode/tap-escrow-manager
  git clone git@github.com:edgeandnode/tap-escrow-manager build/edgeandnode/tap-escrow-manager --branch 'main'
fi

. ./.env
until curl -s "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done

echo "awaiting network subgraph"
export network_subgraph="$(curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/graph_subgraph")"
echo "network_subgraph=${network_subgraph}"

echo "awaiting escrow subgraph"
export escrow_subgraph="$(curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/escrow_subgraph")"
echo "escrow_subgraph=${escrow_subgraph}"

echo "awaiting graph_contracts"
graph_contracts="$(curl -s http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/graph_contracts)"
token_contract="$(echo "${graph_contracts}" | jq -r '."1337".GraphToken.address')"

echo "awaiting scalar-tap-contracts"
tap_contracts="$(curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/scalar_tap_contracts")"
export escrow="$(echo "${tap_contracts}" | jq -r '.escrow')"
echo "escrow=${escrow}"

export GATEWAY_SENDER=${GATEWAY_SENDER_SECRET_KEY#0x}
echo "GATEWAY_SENDER=${GATEWAY_SENDER}"


export KAFKA_TOPIC="gateway_indexer_attempts"
export BOOTSTRAP_SERVERS="${DOCKER_GATEWAY_HOST}:${REDPANDA_KAFKA}"
rpk topic create $KAFKA_TOPIC --brokers=$BOOTSTRAP_SERVERS || true

# Fund the gateway with ETH and GRT
echo "Fund gateway with ETH"
cast send \
  --rpc-url="http://${DOCKER_GATEWAY_HOST}:${CHAIN_RPC}" \
  --private-key="${ACCOUNT0_SECRET_KEY}" \
  "${GATEWAY_SENDER_ADDRESS}" \
  --value '1ether'
echo "Fund gateway with GRT"
cast send \
  --rpc-url="http://${DOCKER_GATEWAY_HOST}:${CHAIN_RPC}" \
  --private-key="${ACCOUNT0_SECRET_KEY}" \
  "${token_contract}" \
  'transfer(address,uint256)' \
  "${GATEWAY_SENDER_ADDRESS}" \
  '1000000000000000000000000'
echo "Approve escrow contract to use GRT"
cast send \
  --rpc-url="http://${DOCKER_GATEWAY_HOST}:${CHAIN_RPC}" \
  --private-key="${GATEWAY_SENDER_SECRET_KEY}" \
  "${token_contract}" \
  'approve(address,uint256)' \
  "${escrow}" \
  '1000000000000000000000000'

cd build/edgeandnode/tap-escrow-manager

envsubst <../../../tap-escrow-manager/config.jsonnet >config.jsonnet
jsonnet config.jsonnet >config.json
cat config.json

export RUST_LOG=info,tap_escrow_manager=trace
cargo run --bin tap-escrow-manager config.json
