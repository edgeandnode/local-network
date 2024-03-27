#!/bin/sh
set -euf

. ./.env
cd build/graphprotocol/indexer

yarn
cd packages/indexer-service

echo "awaiting graph_contracts"
curl "http://controller:${CONTROLLER}/graph_contracts" > addresses.json
echo "awaiting graph_subgraph"
network_subgraph="$(curl "http://controller:${CONTROLLER}/graph_subgraph")"
echo "network_subgraph=${network_subgraph}"
echo "awaiting block_oracle_subgraph"
block_oracle_subgraph="$(curl "http://controller:${CONTROLLER}/block_oracle_subgraph")"
echo "block_oracle_subgraph=${block_oracle_subgraph}"

export INDEXER_SERVICE_ADDRESS_BOOK=addresses.json
export INDEXER_SERVICE_CLIENT_SIGNER_ADDRESS="${GATEWAY_SIGNER_ADDRESS}"
export INDEXER_SERVICE_ETHEREUM="http://chain:${CHAIN_RPC}"
export INDEXER_SERVICE_ETHEREUM_NETWORK=hardhat
export INDEXER_SERVICE_FREE_QUERY_AUTH_TOKEN=freestuff
export INDEXER_SERVICE_GRAPH_NODE_QUERY_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL}"
export INDEXER_SERVICE_GRAPH_NODE_STATUS_ENDPOINT="http://graph-node:${GRAPH_NODE_STATUS}/graphql"
export INDEXER_SERVICE_INDEXER_ADDRESS="${ACCOUNT0_ADDRESS}"
export INDEXER_SERVICE_LOG_LEVEL=trace
export INDEXER_SERVICE_METRICS_PORT=
export INDEXER_SERVICE_MNEMONIC="${MNEMONIC}"
export INDEXER_SERVICE_NETWORK_SUBGRAPH_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/id/${network_subgraph}"
export INDEXER_SERVICE_NETWORK_SUBGRAPH_DEPLOYMENT="${network_subgraph}"
export INDEXER_SERVICE_PORT=${INDEXER_SERVICE}
export INDEXER_SERVICE_POSTGRES_DATABASE=indexer_components_0
export INDEXER_SERVICE_POSTGRES_HOST=postgres
export INDEXER_SERVICE_POSTGRES_USERNAME=dev
export INDEXER_SERVICE_POSTGRES_PASSWORD=
export INDEXER_SERVICE_WALLET_WORKER_THREADS=2

yarn start
