#!/bin/sh
set -euf

if [ ! -d "build/edgeandnode/gw-escrow-manager" ]; then
  mkdir -p build/edgeandnode/gw-escrow-manager
  git clone git@github.com:edgeandnode/gw-escrow-manager build/edgeandnode/gw-escrow-manager --branch 'main'
fi

. ./.env

host="${DOCKER_GATEWAY_HOST:-host.docker.internal}"
echo "host=${host}"

echo "awaiting network subgraph"
export network_subgraph="$(curl "http://${host}:${CONTROLLER}/graph_subgraph")"
echo "network_subgraph=${network_subgraph}"

echo "awaiting escrow subgraph"
export escrow_subgraph="$(curl "http://${host}:${CONTROLLER}/escrow_subgraph")"
echo "escrow_subgraph=${escrow_subgraph}"

echo "awaiting graph_contracts"
graph_contracts="$(curl -s http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/graph_contracts)"
token_contract="$(echo "${graph_contracts}" | jq -r '."1337".GraphToken.address')"

echo "awaiting scalar-tap-contracts"
tap_contracts="$(curl "http://${host}:${CONTROLLER}/scalar_tap_contracts")"
export escrow="$(echo "${tap_contracts}" | jq -r '.escrow')"
echo "escrow=${escrow}"

export GATEWAY_SIGNER=${GATEWAY_SIGNER_SECRET_KEY#0x}
echo "GATEWAY_SIGNER=${GATEWAY_SIGNER}"

# Fund the gateway with ETH and GRT
echo "Fund gateway with ETH"
cast send \
  --rpc-url="http://${DOCKER_GATEWAY_HOST}:${CHAIN_RPC}" \
  --private-key="${ACCOUNT0_SECRET_KEY}" \
  "${GATEWAY_SIGNER_ADDRESS}" \
  --value '1ether'
echo "Fund gateway with GRT"
cast send \
  --rpc-url="http://${DOCKER_GATEWAY_HOST}:${CHAIN_RPC}" \
  --private-key="${ACCOUNT0_SECRET_KEY}" \
  "${token_contract}" \
  'transfer(address,uint256)' \
  "${GATEWAY_SIGNER_ADDRESS}" \
  '1000000000000000000000000'
echo "Approve escrow contract to use GRT"
cast send \
  --rpc-url="http://${DOCKER_GATEWAY_HOST}:${CHAIN_RPC}" \
  --private-key="${GATEWAY_SIGNER_SECRET_KEY}" \
  "${token_contract}" \
  'approve(address,uint256)' \
  "${escrow}" \
  '1000000000000000000000000'

cd build/edgeandnode/gw-escrow-manager

envsubst <../../../gw-escrow-manager/config.jsonnet >config.jsonnet
jsonnet config.jsonnet >config.json
cat config.json

export RUST_LOG=info,gw_escrow_manager=trace
cargo watch -x 'run --bin gw-escrow-manager config.json'