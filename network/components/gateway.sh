#!/usr/bin/env bash

set -e

########################################################################
# Configuration

export GATEWAY_STATS_DATABASE=local_network_gateway_stats
export GATEWAY_STATS_DATABASE_USERNAME=$POSTGRES_USERNAME
export GATEWAY_STATS_DATABASE_PASSWORD=$POSTGRES_PASSWORD

export GATEWAY_NETWORK_SUBGRAPH_ENDPOINT=$NETWORK_SUBGRAPH_ENDPOINT
export GATEWAY_NETWORK_SUBGRAPH_AUTH_TOKEN=superdupersecrettoken

export GATEWAY_MNEMONIC=$MNEMONIC
export GATEWAY_ETHEREUM=$ETHEREUM
export GATEWAY_ETHEREUM_NETWORKS=$ETHEREUM_NETWORK:10:$ETHEREUM
export GATEWAY_LOG_LEVEL=debug

########################################################################
# Run

export NODE_ENV=development

# Ensure the local gateway stats database exists and the timescaledb extension is installed
(dropdb $GATEWAY_STATS_DATABASE >/dev/null 2>&1) || true
(createdb $GATEWAY_STATS_DATABASE >/dev/null 2>&1) || true
(psql -U "$POSTGRES_USERNAME" -d $GATEWAY_STATS_DATABASE -c 'create extension timescaledb' >/dev/null 2>&1) || true

cd $GATEWAY_SOURCES

pushd packages/query-engine
yalc add @graphprotocol/common-ts
yarn
popd

pushd packages/gateway

yalc add @graphprotocol/common-ts
yarn
yarn start \
  --name gateway-local \
  --log-level debug \
  --metrics-port 7301 \
  --agent-syncing-api http://localhost:6702/ \
  --stats-database-database $GATEWAY_STATS_DATABASE \
  --stats-database-port 5432 \
  --rate-limiting-window 10000 \
  --rate-limiting-max-queries 10 \
  --query-budget "0.00030" \
	--local true \
  | pino-pretty | tee /tmp/gateway.log
