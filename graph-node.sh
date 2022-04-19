#!/bin/sh
. ./prelude.sh

github_clone graphprotocol/graph-node master
cd build/graphprotocol/graph-node

# export RUSTFLAGS='-L /Applications/Postgres.app/Contents/Versions/13/lib/'
cargo build -p graph-node

await "curl -sf localhost:${ETHEREUM_PORT}" 0
# graph-node has issues if the chain has no blocks, so we just make sure at least one exists
curl "localhost:${ETHEREUM_PORT}" -X POST --data \
  '{"jsonrpc":"2.0","method":"evm_mine","params":[],"id":1}'

await "curl -sf localhost:${IPFS_PORT}" 22
await "curl -sf localhost:${POSTGRES_PORT}" 52

export POSTGRES_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:${POSTGRES_PORT}/local_network_indexer_node_0"
export ETHEREUM_RPC="hardhat:http://localhost:${ETHEREUM_PORT}"
export GRAPH_ETHEREUM_JSON_RPC_TIMEOUT=10
export IPFS="localhost:${IPFS_PORT}"
export GRAPH_IPFS_TIMEOUT=10
export GRAPH_LOG=debug
export GRAPH_LOG_QUERY_TIMING=gql
export GRAPH_ETH_CALL_FULL_LOG=true
export GRAPH_EXPERIMENTAL_SUBGRAPH_VERSION_SWITCHING_MODE=synced
export GRAPH_ALLOW_NON_DETERMINISTIC_IPFS=true
export GRAPH_ALLOW_NON_DETERMINISTIC_FULLTEXT_SEARCH=false

cargo run -p graph-node
