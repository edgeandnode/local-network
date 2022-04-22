#!/bin/sh
. ./prelude.sh

github_clone edgeandnode/gateway theodus/local-network

await_ready common-ts

cd build/edgeandnode/gateway
cd packages/gateway \
		&& yalc link @graphprotocol/common-ts \
		&& yalc link @graphprotocol/contracts \
		&& yalc update \
    && cd -
cd packages/query-engine \
  && yalc link @graphprotocol/common-ts \
  && yalc link @graphprotocol/contracts \
  && yalc update \
  && cd -
yalc link @graphprotocol/common-ts
yalc link @graphprotocol/contracts
yalc update
yarn
cd ../../..

await_ready graph-subgraph

cd build/edgeandnode/gateway/packages/gateway

export GATEWAY_POSTGRES_USERNAME="${POSTGRES_USER}"
export GATEWAY_POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
export GATEWAY_STUDIO_DATABASE_USERNAME="${POSTGRES_USER}"
export GATEWAY_STUDIO_DATABASE_PASSWORD="${POSTGRES_PASSWORD}"
export GATEWAY_NETWORK_SUBGRAPH_ENDPOINT="http://localhost:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/id/${NETWORK_SUBGRAPH_DEPLOYMENT}"
export GATEWAY_NETWORK_SUBGRAPH_AUTH_TOKEN=superdupersecrettoken
export GATEWAY_MNEMONIC="${MNEMONIC}"
export GATEWAY_ETHEREUM="http://localhost:${ETHEREUM_PORT}"
export GATEWAY_ETHEREUM_NETWORKS="${ETHEREUM_NETWORK}:100:http://localhost:${ETHEREUM_PORT}"
export GATEWAY_LOG_LEVEL=debug

yarn agent \
  --name local_gateway \
  --local true \
  --log-level debug \
  --metrics-port "${GATEWAY_AGENT_METRICS_PORT}" \
  --management-port "${GATEWAY_AGENT_MANAGEMENT_PORT}" \
  --syncing-port "${GATEWAY_AGENT_SYNCING_PORT}" \
  --gateway "http://localhost:${GATEWAY_PORT}" \
  --sync-allocations-interval 10000 \
  --minimum-indexer-version 0.15.0 \
	--postgres-database local_network_gateway \
  --studio-database-port 5432 \
  --studio-database-database local_network_subgraph_studio \
  2>&1| pino-pretty | tee /tmp/gateway-agent.log
