#!/bin/sh
set -euf

if [ ! -d "build/graphprotocol/graph-node" ]; then
  mkdir -p build/graphprotocol/graph-node
  git clone git@github.com:graphprotocol/graph-node build/graphprotocol/graph-node --branch master
fi

. ./.env
export ETHEREUM_RPC="hardhat:http://${DOCKER_GATEWAY_HOST:-host.docker.internal}:${CHAIN_RPC}"
export GRAPH_ALLOW_NON_DETERMINISTIC_IPFS=true
export GRAPH_ALLOW_NON_DETERMINISTIC_FULLTEXT_SEARCH=false
export GRAPH_ETH_CALL_FULL_LOG=true
export GRAPH_ETHEREUM_JSON_RPC_TIMEOUT=10
export GRAPH_EXPERIMENTAL_SUBGRAPH_VERSION_SWITCHING_MODE=synced
export GRAPH_IPFS_TIMEOUT=10
export GRAPH_LOG=debug
export GRAPH_LOG_QUERY_TIMING=gql
export IPFS="http://${DOCKER_GATEWAY_HOST:-host.docker.internal}:${IPFS_RPC}"
export POSTGRES_URL="postgresql://dev:@${DOCKER_GATEWAY_HOST:-host.docker.internal}:${POSTGRES}/indexer_node_0"

cd build/graphprotocol/graph-node
cargo run -p graph-node
