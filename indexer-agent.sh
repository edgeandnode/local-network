#!/bin/sh
. ./prelude.sh

github_clone graphprotocol/indexer bcc8f14

await_ready graph-subgraph

cd build/graphprotocol/indexer

cd packages/indexer-agent \
	&& yalc link @graphprotocol/common-ts \
	&& yalc link @graphprotocol/contracts \
	&& yalc update \
	&& cd -
cd packages/indexer-common \
	&& yalc link @graphprotocol/common-ts \
	&& yalc link @graphprotocol/cost-model \
	&& yalc update \
	&& cd -
cd packages/indexer-cli \
	&& yalc link @graphprotocol/common-ts \
	&& yalc update \
	&& cd -
cd packages/indexer-service \
	&& yalc link @graphprotocol/common-ts \
	&& yalc update \
	&& cd -
yarn

cd packages/indexer-agent

export INDEXER_AGENT_POSTGRES_DATABASE=local_network_indexer_components_0
export INDEXER_AGENT_POSTGRES_USERNAME="${POSTGRES_USER}"
export INDEXER_AGENT_POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"

export INDEXER_AGENT_LOG_LEVEL=trace
export INDEXER_AGENT_PUBLIC_INDEXER_URL="http://localhost:${INDEXER_SERVICE_PORT}"
export INDEXER_AGENT_MNEMONIC="${MNEMONIC}"
export INDEXER_AGENT_INDEXER_ADDRESS="${ACCOUNT_ADDRESS}"
export INDEXER_AGENT_COLLECT_RECEIPTS_ENDPOINT="http://localhost:${GATEWAY_PORT}/collect-receipts"

export INDEXER_AGENT_ETHEREUM="http://localhost:${ETHEREUM_PORT}/"
export INDEXER_AGENT_NETWORK_SUBGRAPH_DEPLOYMENT="${NETWORK_SUBGRAPH_DEPLOYMENT}"
export INDEXER_AGENT_NETWORK_SUBGRAPH_ENDPOINT="http://localhost:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/id/${NETWORK_SUBGRAPH_DEPLOYMENT}"
export INDEXER_AGENT_ALLOCATE_ON_NETWORK_SUBGRAPH=true
export INDEXER_AGENT_REBATE_CLAIM_THRESHOLD=0.00001
export INDEXER_AGENT_VOUCHER_REDEMPTION_THRESHOLD=0.00001

yarn start \
  --graph-node-query-endpoint "http://localhost:${GRAPH_NODE_GRAPHQL_PORT}" \
	--graph-node-admin-endpoint "http://localhost:${GRAPH_NODE_STATUS_PORT}" \
	--graph-node-status-endpoint "http://localhost:${GRAPH_NODE_JRPC_PORT}/graphql" \
	--indexer-management-port "${INDEXER_AGENT_MANAGEMENT_PORT}" \
	--indexer-geo-coordinates "${GEO_COORDINATES}" \
	--postgres-host localhost \
	--postgres-port "${POSTGRES_PORT}" \
	--index-node-ids default \
  --log-level debug \
  --dai-contract 0x9e7e607afd22906f7da6f1ec8f432d6f244278be \
	--restake-rewards true \
  --poi-dispute-monitoring false \
  --poi-disputable-epochs 5 \
	--gas-price-max 10 \
  | pino-pretty | tee /tmp/local-net/indexer-agent.log
