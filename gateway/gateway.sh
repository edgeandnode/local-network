#!/usr/bin/env bash

set -e
set -x

########################################################################
# Configuration

GATEWAY_SOURCES=/path/to/local/gateway/repo

# Get these from Jannis or Martynas
GATEWAY_MNEMONIC=
GATEWAY_STATS_DATABASE_HOST=
GATEWAY_STATS_DATABASE_PASSWORD=
GATEWAY_NETWORK_SUBGRAPH_AUTH_TOKEN=

# Mainnet
GATEWAY_ETHEREUM=https://eth-mainnet.alchemyapi.io/v2/mWSH9YlhpXfXymzLxptC1TE2CIy2QuMA \
GATEWAY_NETWORK_SUBGRAPH_ENDPOINT=https://network-subgraph-indexers.network.thegraph.com/network

# Testnet
# GATEWAY_ETHEREUM=https://eth-rinkeby.alchemyapi.io/v2/MbPzjkEmyF891zBE51Q1c5M4IQAEXZ-9 \
# GATEWAY_NETWORK_SUBGRAPH_ENDPOINT=https://network-subgraph-indexers.testnet.thegraph.com/network

########################################################################
# Run

NODE_ENV=development

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
