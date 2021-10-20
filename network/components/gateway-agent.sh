#!/usr/bin/env bash

set -e

########################################################################
# Configuration

export GATEWAY_DATABASE=local_network_gateway
export GATEWAY_POSTGRES_USERNAME=$POSTGRES_USERNAME
export GATEWAY_POSTGRES_PASSWORD=POSTGRES_PASSWORD
export GATEWAY_STUDIO_DATABASE=local_network_subgraph_studio
export GATEWAY_STUDIO_DATABASE_USERNAME=$POSTGRES_USERNAME
export GATEWAY_STUDIO_DATABASE_PASSWORD=$POSTGRES_PASSWORD

export GATEWAY_NETWORK_SUBGRAPH_ENDPOINT=$NETWORK_SUBGRAPH_ENDPOINT
export GATEWAY_NETWORK_SUBGRAPH_AUTH_TOKEN=superdupersecrettoken

export GATEWAY_MNEMONIC=$MNEMONIC
export GATEWAY_ETHEREUM=$ETHEREUM
export GATEWAY_ETHEREUM_NETWORKS=$ETHEREUM_NETWORK:100:$ETHEREUM
export GATEWAY_LOG_LEVEL=debug

########################################################################
# Run

export NODE_ENV=development

# Ensure there is a fresh local gateway and studio databases
(dropdb -h localhost -U $POSTGRES_USERNAME -w $GATEWAY_DATABASE >/dev/null 2>&1) || true
createdb -h localhost -U $POSTGRES_USERNAME -w $GATEWAY_DATABASE

cd $GATEWAY_SOURCES

pushd packages/query-engine
yalc add @graphprotocol/common-ts
yalc add @graphprotocol/indexer-selection
popd

pushd packages/gateway
yalc add @graphprotocol/common-ts
yalc add @graphprotocol/indexer-selection
popd
yarn

pushd packages/gateway
yarn agent \
  --name local_gateway \
  --local true \
  --log-level debug \
  --metrics-port 7302 \
  --gateway http://localhost:6700/ \
  --sync-allocations-interval 10000 \
  --minimum-indexer-version 0.15.0 \
	--postgres-database $GATEWAY_DATABASE \
  --studio-database-port 5432 \
  --studio-database-database $GATEWAY_STUDIO_DATABASE \
  | pino-pretty | tee /tmp/gateway-agent.log
