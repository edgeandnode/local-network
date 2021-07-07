#!/usr/bin/env bash

set -e

#########################################################################
# Configuration

export INDEXER_SOURCES=/path/to/indexer
export INDEXER_SERVICE_LOG_LEVEL=trace

export INDEXER_SERVICE_MNEMONIC=
export INDEXER_SERVICE_INDEXER_ADDRESS=

export INDEXER_SERVICE_NETWORK_SUBGRAPH_DEPLOYMENT=

export INDEXER_SERVICE_CLIENT_SIGNER_ADDRESS=
export INDEXER_SERVICE_FREE_QUERY_AUTH_TOKEN=

# Local Postgres
export INDEXER_SERVICE_POSTGRES_USERNAME=

# Mainnet
# export INDEXER_SERVICE_ETHEREUM_NETWORK=mainnet
# export INDEXER_SERVICE_ETHEREUM=https://eth-mainnet.alchemyapi.io/v2/iemhQFg2k89zAO1-gSngWqkLHTZ-Byc_
# export INDEXER_SERVICE_NETWORK_SUBGRAPH_ENDPOINT=https://gateway.thegraph.com/network

# Testnet
export INDEXER_SERVICE_ETHEREUM_NETWORK=rinkeby
export INDEXER_SERVICE_ETHEREUM=https://eth-rinkeby.alchemyapi.io/v2/MbPzjkEmyF891zBE51Q1c5M4IQAEXZ-9
export INDEXER_SERVICE_NETWORK_SUBGRAPH_ENDPOINT=https://gateway.testnet.thegraph.com/network

########################################################################
# Run

export NODE_ENV=development

# Ensure the local indexer database exists
(createdb indexer >/dev/null 2>&1) || true

cd $INDEXER_SOURCES

pushd packages/indexer-native
yarn
popd

pushd packages/indexer-common
yarn
popd

pushd packages/indexer-service

yarn start \
  --graph-node-admin-endpoint http://localhost:8020/ \
  --graph-node-query-endpoint http://localhost:8000/ \
  --graph-node-status-endpoint http://localhost:8030/graphql \
  --postgres-host localhost \
  --postgres-port 5432 \
  --postgres-database indexer \
  --serve-network-subgraph \
  | tee /tmp/indexer-service.log
