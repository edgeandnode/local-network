#!/bin/sh
. ./prelude.sh

github_clone edgeandnode/graph-gateway

cd build/edgeandnode/graph-gateway
cargo build
cd -

await_ready graph-subgraph

cd build/edgeandnode/graph-gateway

export RUST_LOG=info,graph_gateway=trace
export MNEMONIC="${MNEMONIC}"
export ETHEREUM_PROVIDERS="${ETHEREUM_NETWORK}=http://localhost:${ETHEREUM_PORT}"
export NETWORK_SUBGRAPH_AUTH_TOKEN=superdupersecrettoken
export NETWORK_SUBGRAPH="http://localhost:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/id/${NETWORK_SUBGRAPH_DEPLOYMENT}"
export SYNC_AGENT="http://localhost:${GATEWAY_AGENT_SYNCING_PORT}"
export SYNC_AGENT_ACCEPT_EMPTY=true
export IPFS="http://localhost:${IPFS_PORT}/api/v0/cat?arg="
# export MIPS="0.2:0x90f8bf6a479f320ead074411a4b0e7944ea8c9c1"

export PORT="${GATEWAY_PORT}"
export METRICS_PORT="${GATEWAY_METRICS_PORT}"

export REDPANDA_BROKERS="localhost:${REDPANDA_PORT}"

export STATS_DB_HOST=localhost
export STATS_DB_PORT=5432
export STATS_DB_NAME=local_network_gateway_stats
export STATS_DB_USER="${POSTGRES_USER}"
export STATS_DB_PASSWORD=

export LOCATION_COUNT=1
export REPLICA_COUNT=1

cargo run
