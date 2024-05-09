#!/bin/sh
set -eu
. /opt/.env

export INDEXER_SERVICE_ADDRESS_BOOK=/opt/contracts.json
export INDEXER_SERVICE_CLIENT_SIGNER_ADDRESS="${ACCOUNT0_ADDRESS}"
export INDEXER_SERVICE_ETHEREUM="http://chain:${CHAIN_RPC}"
export INDEXER_SERVICE_ETHEREUM_NETWORK=hardhat
export INDEXER_SERVICE_FREE_QUERY_AUTH_TOKEN=freestuff
export INDEXER_SERVICE_GRAPH_NODE_QUERY_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL}"
export INDEXER_SERVICE_GRAPH_NODE_STATUS_ENDPOINT="http://graph-node:${GRAPH_NODE_STATUS}/graphql"
export INDEXER_SERVICE_INDEXER_ADDRESS="${RECEIVER_ADDRESS}"
export INDEXER_SERVICE_LOG_LEVEL=trace
export INDEXER_SERVICE_METRICS_PORT=
export INDEXER_SERVICE_MNEMONIC="${INDEXER_MNEMONIC}"
export INDEXER_SERVICE_NETWORK_SUBGRAPH_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network"
export INDEXER_SERVICE_PORT="${INDEXER_SERVICE}"
export INDEXER_SERVICE_POSTGRES_DATABASE=indexer_components_1
export INDEXER_SERVICE_POSTGRES_HOST=postgres
export INDEXER_SERVICE_POSTGRES_USERNAME=postgres
export INDEXER_SERVICE_POSTGRES_PASSWORD=

cd /opt/indexer-service-source-root
nodemon --watch . \
--ext js \
--legacy-watch \
--delay 3 \
--exec "ts-node packages/indexer-service/src/index.ts start"
