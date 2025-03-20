#!/bin/sh
set -eu
. /opt/.env

# graph-node has issues if there isn't at least one block on the chain
curl -sf "http://chain:${CHAIN_RPC}" \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"anvil_mine","params":[]}'

export ETHEREUM_RPC="hardhat:http://chain:${CHAIN_RPC}/"
export GRAPH_ALLOW_NON_DETERMINISTIC_FULLTEXT_SEARCH="true"
unset GRAPH_NODE_CONFIG
export IPFS="http://ipfs:${IPFS_RPC}"
export POSTGRES_URL="postgresql://postgres:@postgres:${POSTGRES}/graph_node_1"
graph-node
