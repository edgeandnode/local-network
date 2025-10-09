#!/bin/sh
set -eu
. /opt/.env

export ETHEREUM_RPC="mainnet:${MAINNET_RPC}"
export GRAPH_ALLOW_NON_DETERMINISTIC_FULLTEXT_SEARCH="true"
unset GRAPH_NODE_CONFIG
export IPFS="https://ipfs.thegraph.com"
export POSTGRES_URL="postgresql://postgres:@postgres:${POSTGRES}/graph_node_1"
graph-node
