#!/usr/bin/env bash
source prelude.bash

cd projects/graphprotocol/indexer/packages/indexer-service

export NODE_ENV=development

export INDEXER_SERVICE_MNEMONIC="${MNEMONIC}"
export INDEXER_SERVICE_INDEXER_ADDRESS="${ACCOUNT_ADDRESS}"
export INDEXER_SERVICE_LOG_LEVEL=trace

export INDEXER_SERVICE_POSTGRES_USERNAME="${POSTGRES_USERNAME}"
export INDEXER_SERVICE_POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
export SERVER_DB_USER="${POSTGRES_USERNAME}"
export SERVER_DB_PASSWORD="${POSTGRES_PASSWORD}"
export INDEXER_SERVICE_POSTGRES_HOST=localhost

export INDEXER_SERVICE_ETHEREUM="${ETHEREUM}"
# export INDEXER_SERVICE_ETHEREUM_NETWORK="${ETHEREUM_NETWORK_ID}"
export INDEXER_SERVICE_NETWORK_SUBGRAPH_DEPLOYMENT="${NETWORK_SUBGRAPH_DEPLOYMENT}"
export INDEXER_SERVICE_NETWORK_SUBGRAPH_ENDPOINT="${NETWORK_SUBGRAPH}"

export INDEXER_SERVICE_CLIENT_SIGNER_ADDRESS=0x5D0365E8DCBD1b00FC780b206e85c9d78159a865
export INDEXER_SERVICE_FREE_QUERY_AUTH_TOKEN=superdupersecrettoken

yarn start \
  --port "${INDEXER_SERVICE_PORT}" \
  --metrics-port "${INDEXER_METRICS_PORT}" \
  --wallet-worker-threads 2 \
  --postgres-database local_network_indexer_0_components \
  --graph-node-query-endpoint "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}" \
  --graph-node-status-endpoint "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_JRPC_PORT}/graphql" \
  --log-level debug \
  | pino-pretty | tee /tmp/indexer-service.log
