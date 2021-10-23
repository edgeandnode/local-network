#!/usr/bin/env bash
source prelude.bash

cd projects/graphprotocol/graph-node

POSTGRES_URL="postgresql://${POSTGRES_USERNAME}:${POSTGRES_PASSWORD}@localhost:5432/local_network_indexer_0_node"
# export RUSTFLAGS='-L /Applications/Postgres.app/Contents/Versions/13/lib/'

export GRAPH_ALLOW_NON_DETERMINISTIC_IPFS=true
export GRAPH_ALLOW_NON_DETERMINISTIC_FULLTEXT_SEARCH=true
export GRAPH_ETH_CALL_FULL_LOG=true
export GRAPH_EXPERIMENTAL_SUBGRAPH_VERSION_SWITCHING_MODE=synced
export GRAPH_LOG=debug
export GRAPH_LOG_QUERY_TIMING=gql

cargo run -p graph-node -- \
  --ethereum-rpc "${ETHEREUM_NETWORK}":"${ETHEREUM}" \
  --ipfs "${IPFS}" \
  --postgres-url "${POSTGRES_URL}" \
  --http-port "${GRAPH_NODE_GRAPHQL_PORT}" \
  --admin-port "${GRAPH_NODE_STATUS_PORT}" \
  --index-node-port "${GRAPH_NODE_JRPC_PORT}" \
  --metrics-port "${GRAPH_NODE_METRICS_PORT}" \
  |& tee /tmp/graph-node.log
