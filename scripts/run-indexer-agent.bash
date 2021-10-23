#!/usr/bin/env bash
source prelude.bash

cd projects/graphprotocol/indexer/packages/indexer-agent

export NODE_ENV=development

export INDEXER_AGENT_POSTGRES_DATABASE=local_network_indexer_0_components
export INDEXER_AGENT_POSTGRES_USERNAME="${POSTGRES_USERNAME}"
export INDEXER_AGENT_POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"

export INDEXER_AGENT_LOG_LEVEL=trace
export INDEXER_AGENT_PUBLIC_INDEXER_URL="${INDEXER_SERVICE_HOST}:${INDEXER_SERVICE_PORT}"
export INDEXER_AGENT_MNEMONIC="${MNEMONIC}"
export INDEXER_AGENT_INDEXER_ADDRESS="${ACCOUNT_ADDRESS}"
export INDEXER_AGENT_COLLECT_RECEIPTS_ENDPOINT="${GATEWAY}/collect-receipts"


export INDEXER_AGENT_ETHEREUM_NETWORK=any
export INDEXER_AGENT_ETHEREUM="${ETHEREUM}"
export INDEXER_AGENT_NETWORK_SUBGRAPH_DEPLOYMENT="${NETWORK_SUBGRAPH_DEPLOYMENT}"
export INDEXER_AGENT_NETWORK_SUBGRAPH_ENDPOINT="${NETWORK_SUBGRAPH}"

yarn start \
  --graph-node-query-endpoint "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}" \
	--graph-node-admin-endpoint "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_STATUS_PORT}" \
	--graph-node-status-endpoint "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_JRPC_PORT}/graphql" \
	--indexer-management-port "${INDEXER_AGENT_MANAGEMENT_PORT}" \
	--indexer-geo-coordinates 118.2923 36.5785  \
	--postgres-host localhost \
	--postgres-port 5432 \
	--index-node-ids default \
  --log-level debug \
  --dai-contract 0x9e7e607afd22906f7da6f1ec8f432d6f244278be \
	--restake-rewards true \
  --poi-dispute-monitoring true \
  --poi-disputable-epochs 5 \
	--gas-price-max 10 \
  | pino-pretty | tee /tmp/indexer-agent.log
