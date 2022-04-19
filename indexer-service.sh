#!/bin/sh
. ./prelude.sh

await "curl -sf localhost:${INDEXER_AGENT_MANAGEMENT_PORT} > /dev/null"

cd build/graphprotocol/indexer/packages/indexer-service

export NODE_ENV=development

export INDEXER_SERVICE_MNEMONIC="${MNEMONIC}"
export INDEXER_SERVICE_INDEXER_ADDRESS="${ACCOUNT_ADDRESS}"
export INDEXER_SERVICE_LOG_LEVEL=trace

export INDEXER_SERVICE_POSTGRES_USERNAME="${POSTGRES_USER}"
export INDEXER_SERVICE_POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
export SERVER_DB_USER="${POSTGRES_USER}"
export SERVER_DB_PASSWORD="${POSTGRES_PASSWORD}"
export INDEXER_SERVICE_POSTGRES_HOST=localhost

export INDEXER_SERVICE_ETHEREUM="http://localhost:${ETHEREUM_PORT}"
# export INDEXER_SERVICE_ETHEREUM_NETWORK="${ETHEREUM_NETWORK_ID}"
export INDEXER_SERVICE_NETWORK_SUBGRAPH_DEPLOYMENT="${NETWORK_SUBGRAPH_DEPLOYMENT}"
export INDEXER_SERVICE_NETWORK_SUBGRAPH_ENDPOINT="http://localhost:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/id/${NETWORK_SUBGRAPH_DEPLOYMENT}"

export INDEXER_SERVICE_CLIENT_SIGNER_ADDRESS=0x5D0365E8DCBD1b00FC780b206e85c9d78159a865
export INDEXER_SERVICE_FREE_QUERY_AUTH_TOKEN=superdupersecrettoken

yarn start \
  --port "${INDEXER_SERVICE_PORT}" \
  --metrics-port "${INDEXER_METRICS_PORT}" \
  --wallet-worker-threads 2 \
  --postgres-database local_network_indexer_components_0 \
  --graph-node-query-endpoint "http://localhost:${GRAPH_NODE_GRAPHQL_PORT}" \
  --graph-node-status-endpoint "http://localhost:${GRAPH_NODE_JRPC_PORT}/graphql" \
  --log-level debug \
  | pino-pretty | tee /tmp/local-network/indexer-service.log
