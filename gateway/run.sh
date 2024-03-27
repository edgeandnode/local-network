#!/bin/sh
set -euf

. ./.env
cd build/edgeandnode/graph-gateway

dispute_manager="$(curl "http://controller:${CONTROLLER}/graph_contracts" | jq -r '."1337".DisputeManager.address')"
export DISPUTE_MANAGER="${dispute_manager}"
export GATEWAY_SIGNER=${ACCOUNT1_SECRET_KEY}
export GRAPH_NODE_GRAPHQL=${GRAPH_NODE_GRAPHQL}
export IPFS_RPC=${IPFS_RPC}
export REDPANDA_KAFKA=${REDPANDA_KAFKA}

envsubst <../../../config.jsonnet >config.jsonnet
jsonnet config.jsonnet >config.json
export RUST_LOG=info,graph_gateway=trace,gateway_framework=trace,gateway_framework::chains::ethereum::json_rpc=info
cargo run --bin graph-gateway config.json
