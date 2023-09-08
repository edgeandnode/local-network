#!/bin/sh
set -euf

if [ ! -d "build/graphprotocol/indexer" ]; then
  mkdir -p build/graphprotocol/indexer
  git clone git@github.com:graphprotocol/indexer build/graphprotocol/indexer --branch 'theodus/local-net'
fi

# TODO: temporary hack
if [ ! -d "build/graphprotocol/common-ts" ]; then
  mkdir -p build/graphprotocol/common-ts
  git clone git@github.com:graphprotocol/common-ts build/graphprotocol/common-ts --branch 'theodus/local-net'
fi
(cd build/graphprotocol/common-ts/ && yarn)

. ./.env
host="${DOCKER_GATEWAY_HOST:-host.docker.internal}"

curl "http://${host}:${CONTROLLER}/graph_addresses" > addresses.json

cd build/graphprotocol/indexer
yarn

cd packages/indexer-service

network_subgraph="$(curl "http://${host}:${CONTROLLER}/graph_subgraph_deployment")"
echo "network_subgraph=${network_subgraph}"
block_oracle_subgraph="$(curl "http://${host}:${CONTROLLER}/block_oracle_subgraph_deployment")"
echo "block_oracle_subgraph=${block_oracle_subgraph}"

../indexer-cli/bin/graph-indexer indexer connect "http://${host}:${INDEXER_MANAGEMENT}"
../indexer-cli/bin/graph-indexer --network=hardhat indexer rules set global \
  decisionBasis rules minSignal 0 allocationAmount 1
../indexer-cli/bin/graph-indexer --network=hardhat indexer rules set "${network_subgraph}" \
  decisionBasis always
../indexer-cli/bin/graph-indexer --network=hardhat indexer rules prepare "${block_oracle_subgraph}"

export INDEXER_SERVICE_ADDRESS_BOOK=../../../../../addresses.json
export INDEXER_SERVICE_CLIENT_SIGNER_ADDRESS="0x5D0365E8DCBD1b00FC780b206e85c9d78159a865"
export INDEXER_SERVICE_ETHEREUM="http://${host}:${CHAIN_RPC}"
export INDEXER_SERVICE_ETHEREUM_NETWORK=hardhat
export INDEXER_SERVICE_FREE_QUERY_AUTH_TOKEN=freestuff
export INDEXER_SERVICE_GRAPH_NODE_QUERY_ENDPOINT="http://${host}:${GRAPH_NODE_GRAPHQL}"
export INDEXER_SERVICE_GRAPH_NODE_STATUS_ENDPOINT="http://${host}:${GRAPH_NODE_STATUS}/graphql"
export INDEXER_SERVICE_INDEXER_ADDRESS="${ACCOUNT0_ADDRESS}"
export INDEXER_SERVICE_LOG_LEVEL=trace
export INDEXER_SERVICE_METRICS_PORT=
export INDEXER_SERVICE_MNEMONIC="${ACCOUNT0_MNEMONIC}"
export INDEXER_SERVICE_NETWORK_SUBGRAPH_ENDPOINT="http://${host}:${GRAPH_NODE_GRAPHQL}/subgraphs/id/${network_subgraph}"
export INDEXER_SERVICE_NETWORK_SUBGRAPH_DEPLOYMENT="${network_subgraph}"
export INDEXER_SERVICE_PORT=${INDEXER_SERVICE}
export INDEXER_SERVICE_POSTGRES_DATABASE=indexer_components_0
export INDEXER_SERVICE_POSTGRES_HOST="${host}"
export INDEXER_SERVICE_POSTGRES_USERNAME=dev
export INDEXER_SERVICE_POSTGRES_PASSWORD=
export INDEXER_SERVICE_WALLET_WORKER_THREADS=2

yarn start | npx pino-pretty
