#!/usr/bin/env bash

set -e

#########################################################################
# Configuration

export INDEXER_AGENT_LOG_LEVEL=trace
export INDEXER_AGENT_PUBLIC_INDEXER_URL=http://localhost:7600/
export INDEXER_AGENT_MNEMONIC=$MNEMONIC
export INDEXER_AGENT_INDEXER_ADDRESS=$ACCOUNT_ADDRESS
export INDEXER_AGENT_COLLECT_RECEIPTS_ENDPOINT=$GATEWAY_ENDPOINT/collect-receipts \

# DB
export INDEXER_DB_NAME=local_network_indexer_0_components
export INDEXER_AGENT_POSTGRES_USERNAME=$POSTGRES_USERNAME
export INDEXER_AGENT_POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# Network
export INDEXER_AGENT_ETHEREUM_NETWORK=$ETHEREUM_NETWORK
export INDEXER_AGENT_ETHEREUM=$ETHEREUM
export INDEXER_AGENT_ETHEREUM_NETWORK=$ETHEREUM_NETWORK
export INDEXER_AGENT_NETWORK_SUBGRAPH_DEPLOYMENT=$NETWORK_SUBGRAPH
export INDEXER_AGENT_NETWORK_SUBGRAPH_ENDPOINT=$NETWORK_SUBGRAPH_ENDPOINT
export INDEXER_AGENT_ETHEREUM_NETWORK=any

########################################################################
# Run

export NODE_ENV=development

# Ensure there is a fresh local indexer database
(dropdb $INDEXER_DB_NAME >/dev/null 2>&1) || true
(createdb $INDEXER_DB_NAME >/dev/null 2>&1) || true

cd $COMMON_TS_SOURCES

yalc publish

cd $INDEXER_SOURCES

yarn

pushd packages/indexer-common
yalc add @graphprotocol/common-ts
yarn
popd

pushd packages/indexer-agent
yalc add @graphprotocol/contracts
yalc add @graphprotocol/common-ts
yarn

yarn start \
  --graph-node-query-endpoint http://localhost:8000/ \
	--graph-node-admin-endpoint http://localhost:8020/ \
	--graph-node-status-endpoint http://localhost:8030/graphql \
	--public-indexer-url http://localhost:7600/ \
	--indexer-management-port 18000 \
	--indexer-geo-coordinates 118.2923 36.5785  \
	--postgres-host localhost \
	--postgres-port 5432 \
	--postgres-database $INDEXER_DB_NAME \
	--index-node-ids default \
  --log-level debug \
  --dai-contract 0x9e7e607afd22906f7da6f1ec8f432d6f244278be \
	--restake-rewards true \
  --poi-dispute-monitoring true \
  --poi-disputable-epochs 5 \
	--gas-price-max 10 \
  | pino-pretty | tee /tmp/indexer-agent.log
