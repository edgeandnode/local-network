#!/usr/bin/env bash
source prelude.bash

cd projects/edgeandnode/graph-gateway

export RUST_LOG=info,graph_gateway=trace
export MNEMONIC="${MNEMONIC}"
export ETHEREUM_PROVIDERS="${ETHEREUM_NETWORK}=${ETHEREUM}"
export NETWORK_SUBGRAPH_AUTH_TOKEN=superdupersecrettoken
export SYNC_AGENT="http://localhost:${GATEWAY_AGENT_SYNCING_PORT}"

export PORT="${GATEWAY_PORT}"
export METRICS_PORT="${GATEWAY_METRICS_PORT}"

export STATS_DB_HOST=localhost
export STATS_DB_PORT=5432
export STATS_DB_NAME=local_network_gateway_stats
export STATS_DB_USER="${POSTGRES_USERNAME}"
export STATS_DB_PASSWORD=

cargo run |& tee /tmp/gateway.log
