#!/bin/sh
set -euf

if [ ! -d "build/graphprotocol/indexer" ]; then
  mkdir -p build/graphprotocol/indexer
  git clone git@github.com:graphprotocol/indexer build/graphprotocol/indexer --branch 'main'
fi

. ./.env

until curl -s "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done

cd build/graphprotocol/indexer
yarn
cd packages/indexer-service

echo "awaiting graph_contracts"
curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/graph_contracts" >addresses.json
echo "awaiting graph_subgraph"
network_subgraph="$(curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/graph_subgraph")"
echo "network_subgraph=${network_subgraph}"
echo "awaiting block_oracle_subgraph"
block_oracle_subgraph="$(curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/block_oracle_subgraph")"
echo "block_oracle_subgraph=${block_oracle_subgraph}"

export INDEXER_SERVICE_ADDRESS_BOOK=addresses.json
export INDEXER_SERVICE_CLIENT_SIGNER_ADDRESS="${GATEWAY_SIGNER_ADDRESS}"
export INDEXER_SERVICE_ETHEREUM="http://${DOCKER_GATEWAY_HOST}:${CHAIN_RPC}"
export INDEXER_SERVICE_ETHEREUM_NETWORK=hardhat
export INDEXER_SERVICE_FREE_QUERY_AUTH_TOKEN=freestuff
export INDEXER_SERVICE_GRAPH_NODE_QUERY_ENDPOINT="http://${DOCKER_GATEWAY_HOST}:${GRAPH_NODE_GRAPHQL}"
export INDEXER_SERVICE_GRAPH_NODE_STATUS_ENDPOINT="http://${DOCKER_GATEWAY_HOST}:${GRAPH_NODE_STATUS}/graphql"
export INDEXER_SERVICE_INDEXER_ADDRESS="${ACCOUNT0_ADDRESS}"
export INDEXER_SERVICE_LOG_LEVEL=trace
export INDEXER_SERVICE_METRICS_PORT=
export INDEXER_SERVICE_MNEMONIC="${MNEMONIC}"
export INDEXER_SERVICE_NETWORK_SUBGRAPH_ENDPOINT="http://${DOCKER_GATEWAY_HOST}:${GRAPH_NODE_GRAPHQL}/subgraphs/id/${network_subgraph}"
export INDEXER_SERVICE_NETWORK_SUBGRAPH_DEPLOYMENT="${network_subgraph}"
export INDEXER_SERVICE_PORT=${INDEXER_SERVICE}
export INDEXER_SERVICE_POSTGRES_DATABASE=indexer_components_0
export INDEXER_SERVICE_POSTGRES_HOST="${DOCKER_GATEWAY_HOST}"
export INDEXER_SERVICE_POSTGRES_USERNAME=dev
export INDEXER_SERVICE_POSTGRES_PASSWORD=
export INDEXER_SERVICE_WALLET_WORKER_THREADS=2

yarn start | npx pino-pretty
