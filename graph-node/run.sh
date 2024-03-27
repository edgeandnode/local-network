#!/bin/sh
set -euf

. ./.env

while !(curl -f http://ipfs:5001/version && pg_isready -h postgres); do sleep 1; done

# graph-node has issues if there isn't at least one block on the chain
until curl -s "chain:${CHAIN_RPC}" > /dev/null; do sleep 1; done
curl "chain:${CHAIN_RPC}" \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"anvil_mine","params":[]}'

export ETHEREUM_RPC="hardhat:http://chain:${CHAIN_RPC}"
export GRAPH_ETH_CALL_FULL_LOG=false
export GRAPH_ETHEREUM_JSON_RPC_TIMEOUT=10
export GRAPH_EXPERIMENTAL_SUBGRAPH_VERSION_SWITCHING_MODE=synced
export GRAPH_IPFS_TIMEOUT=10
export GRAPH_LOG=debug
export GRAPH_LOG_QUERY_TIMING=gql
export GRAPH_NODE_ID=default
export IPFS="http://ipfs:${IPFS_RPC}"
export POSTGRES_URL="postgresql://dev:@postgres:${POSTGRES}/graph_node_1"

cd build/graphprotocol/graph-node
cargo run -p graph-node
