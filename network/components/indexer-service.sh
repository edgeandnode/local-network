#!/usr/bin/env bash

set -e

#########################################################################
# Configuration

export INDEXER_SERVICE_MNEMONIC=$MNEMONIC
export INDEXER_SERVICE_INDEXER_ADDRESS=$ACCOUNT_ADDRESS
export INDEXER_SERVICE_LOG_LEVEL=trace

# Local Postgres
export INDEXER_DB_NAME=local_network_indexer_0_components
export INDEXER_SERVICE_POSTGRES_USERNAME=$POSTGRES_USERNAME
export INDEXER_SERVICE_POSTGRES_PASSWORD=$POSTGRES_PASSWORD
export SERVER_HOST=localhost
export SERVER_PORT=5432
export SERVER_DB_NAME=local_network_indexer_0_components
export SERVER_DB_USER=$POSTGRES_USERNAME
export SERVER_DB_PASSWORD=$POSTGRES_PASSWORD

# Network
export INDEXER_SERVICE_ETHEREUM=$ETHEREUM
export INDEXER_SERVICE_NETWORK_SUBGRAPH_DEPLOYMENT=$NETWORK_SUBGRAPH
export INDEXER_SERVICE_NETWORK_SUBGRAPH_ENDPOINT=$NETWORK_SUBGRAPH_ENDPOINT

export INDEXER_SERVICE_CLIENT_SIGNER_ADDRESS=0x5D0365E8DCBD1b00FC780b206e85c9d78159a865
export INDEXER_SERVICE_FREE_QUERY_AUTH_TOKEN=superdupersecrettoken

########################################################################
# Run

export NODE_ENV=development

# Ensure the local indexer database exists
(createdb $INDEXER_DB_NAME >/dev/null 2>&1) || true

cd $INDEXER_SOURCES

pushd packages/indexer-native
yarn
popd

pushd packages/indexer-common
yalc add @graphprotocol/common-ts
yarn
popd

pushd packages/indexer-service

yalc add @graphprotocol/common-ts
yarn start \
  --port 7600 \
  --metrics-port 7700 \
  --wallet-worker-threads 2 \
  --postgres-database $INDEXER_DB_NAME \
  --postgres-host localhost \
  --postgres-port 5432 \
  --graph-node-query-endpoint http://localhost:8000/ \
  --graph-node-status-endpoint http://localhost:8030/graphql \
  --log-level debug \
  | pino-pretty | tee /tmp/indexer-service.log
