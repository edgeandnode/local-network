#!/usr/bin/env bash

set -e

#########################################################################
# Configuration

export INDEXER_SOURCES=/path/to/indexer
export INDEXER_AGENT_LOG_LEVEL=trace

export INDEXER_AGENT_PUBLIC_INDEXER_URL=http://localhost:7600/
export INDEXER_AGENT_MNEMONIC=
export INDEXER_AGENT_INDEXER_ADDRESS=
export INDEXER_AGENT_INDEXER_GEO_COORDINATES=

export INDEXER_AGENT_NETWORK_SUBGRAPH_DEPLOYMENT=

# Local Postgres
export INDEXER_AGENT_POSTGRES_USERNAME=

# Mainnet
# export INDEXER_AGENT_ETHEREUM_NETWORK=mainnet
# export INDEXER_AGENT_ETHEREUM=https://eth-mainnet.alchemyapi.io/v2/iemhQFg2k89zAO1-gSngWqkLHTZ-Byc_
# export INDEXER_AGENT_NETWORK_SUBGRAPH_ENDPOINT=https://gateway.thegraph.com/network
# export INDEXER_AGENT_COLLECT_RECEIPTS_ENDPOINT=https://gateway.testnet.thegraph.com/collect-receipts \

# Testnet
export INDEXER_AGENT_ETHEREUM_NETWORK=rinkeby
export INDEXER_AGENT_ETHEREUM=https://eth-rinkeby.alchemyapi.io/v2/MbPzjkEmyF891zBE51Q1c5M4IQAEXZ-9
export INDEXER_AGENT_NETWORK_SUBGRAPH_ENDPOINT=https://gateway.testnet.thegraph.com/network
export INDEXER_AGENT_COLLECT_RECEIPTS_ENDPOINT=https://gateway.testnet.thegraph.com/collect-receipts \

########################################################################
# Run

export NODE_ENV=development

# Ensure the local indexer database exists
(createdb indexer >/dev/null 2>&1) || true

cd $INDEXER_SOURCES

pushd packages/indexer-common
yarn
popd

pushd packages/indexer-agent

yarn start \
  --graph-node-admin-endpoint http://localhost:8020/ \
  --graph-node-query-endpoint http://localhost:8000/ \
  --graph-node-status-endpoint http://localhost:8030/graphql \
  --postgres-host localhost \
  --postgres-port 5432 \
  --postgres-database indexer \
  --index-node-ids default \
  --indexer-management-port 18000 \
  --syncing-port 18001 \
  | tee /tmp/indexer-agent.log
