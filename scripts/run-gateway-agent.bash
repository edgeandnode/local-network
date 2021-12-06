#!/usr/bin/env bash
source prelude.bash

cd projects/edgeandnode/gateway/packages/gateway

export NODE_ENV=development

GATEWAY_DATABASE=local_network_gateway
GATEWAY_STUDIO_DATABASE=local_network_subgraph_studio
export GATEWAY_POSTGRES_USERNAME="${POSTGRES_USERNAME}"
export GATEWAY_POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
export GATEWAY_STUDIO_DATABASE_USERNAME="${POSTGRES_USERNAME}"
export GATEWAY_STUDIO_DATABASE_PASSWORD="${POSTGRES_PASSWORD}"
export GATEWAY_NETWORK_SUBGRAPH_ENDPOINT="${NETWORK_SUBGRAPH}"
export GATEWAY_NETWORK_SUBGRAPH_AUTH_TOKEN=superdupersecrettoken
export GATEWAY_MNEMONIC="${MNEMONIC}"
export GATEWAY_ETHEREUM="${ETHEREUM}"
export GATEWAY_ETHEREUM_NETWORKS="${ETHEREUM_NETWORK}:100:${ETHEREUM}"
export GATEWAY_LOG_LEVEL=debug

yarn agent \
  --name local_gateway \
  --local true \
  --log-level debug \
  --metrics-port "${GATEWAY_AGENT_METRICS_PORT}" \
  --management-port "${GATEWAY_AGENT_MANAGEMENT_PORT}" \
  --syncing-port "${GATEWAY_AGENT_SYNCING_PORT}" \
  --gateway "http://${GATEWAY_HOST}:${GATEWAY_PORT}" \
  --sync-allocations-interval 10000 \
  --minimum-indexer-version 0.15.0 \
	--postgres-database "${GATEWAY_DATABASE}" \
  --studio-database-port 5432 \
  --studio-database-database "${GATEWAY_STUDIO_DATABASE}" \
  2>&1| pino-pretty | tee /tmp/gateway-agent.log
