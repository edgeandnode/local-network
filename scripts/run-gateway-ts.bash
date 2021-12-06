#!/usr/bin/env bash
source prelude.bash

cd projects/edgeandnode/gateway/packages/gateway

export NODE_ENV=development

GATEWAY_STATS_DATABASE=local_network_gateway_stats

export GATEWAY_STATS_DATABASE_USERNAME="${POSTGRES_USERNAME}"
export GATEWAY_STATS_DATABASE_PASSWORD="${POSTGRES_PASSWORD}"

export GATEWAY_NETWORK_SUBGRAPH_ENDPOINT="${NETWORK_SUBGRAPH}"
export GATEWAY_NETWORK_SUBGRAPH_AUTH_TOKEN=superdupersecrettoken

export GATEWAY_MNEMONIC="${MNEMONIC}"
export GATEWAY_ETHEREUM="${ETHEREUM}"
export GATEWAY_ETHEREUM_NETWORKS="${ETHEREUM_NETWORK}:10:${ETHEREUM}"
export GATEWAY_LOG_LEVEL=trace
export GATEWAY_ASYNC_LOGGING=true

yarn start \
  --name gateway-local \
  --port "${GATEWAY_PORT}" \
  --metrics-port "${GATEWAY_METRICS_PORT}" \
  --agent-syncing-api "http://localhost:${GATEWAY_AGENT_SYNCING_PORT}" \
  --stats-database-database "${GATEWAY_STATS_DATABASE}" \
  --rate-limiting-window 10000 \
  --rate-limiting-max-queries 10 \
  --query-budget "0.00030" \
	--local true \
  2>&1| pino-pretty | tee /tmp/gateway-ts.log
