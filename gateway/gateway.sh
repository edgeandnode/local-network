#!/usr/bin/env bash

set -e

########################################################################
# Configuration

export GATEWAY_SOURCES=/path/to/gateway
export GATEWAY_LOG_LEVEL=debug

# Get these from Jannis or Martynas
export GATEWAY_MNEMONIC=
export GATEWAY_STATS_DATABASE_HOST=
export GATEWAY_STATS_DATABASE_PASSWORD=
export GATEWAY_NETWORK_SUBGRAPH_AUTH_TOKEN=

# Mainnet
export GATEWAY_ETHEREUM=https://eth-mainnet.alchemyapi.io/v2/mWSH9YlhpXfXymzLxptC1TE2CIy2QuMA \
export GATEWAY_NETWORK_SUBGRAPH_ENDPOINT=https://network-subgraph-indexers.network.thegraph.com/network

# Testnet
# export GATEWAY_ETHEREUM=https://eth-rinkeby.alchemyapi.io/v2/MbPzjkEmyF891zBE51Q1c5M4IQAEXZ-9 \
# export GATEWAY_NETWORK_SUBGRAPH_ENDPOINT=https://network-subgraph-indexers.testnet.thegraph.com/network

########################################################################
# Run

export NODE_ENV=development

cd $GATEWAY_SOURCES

pushd packages/query-engine
yarn
popd

pushd packages/gateway

yarn start \
  --name gateway-local \
  --log-level debug \
  --metrics-port 7301 \
  --agent-syncing-api http://localhost:6702/ \
  --ethereum https://eth-mainnet.alchemyapi.io/v2/mWSH9YlhpXfXymzLxptC1TE2CIy2QuMA \
  --ethereum-networks mainnet:15:https://eth-mainnet.alchemyapi.io/v2/mWSH9YlhpXfXymzLxptC1TE2CIy2QuMA \
  --stats-database-port 16188 \
  --stats-database-database defaultdb \
  --stats-database-username tsdbadmin \
  --rate-limiting-window 10000 \
  --rate-limiting-max-queries 10 \
  --query-budget "0.00030" \
  | tee /tmp/gateway.log
