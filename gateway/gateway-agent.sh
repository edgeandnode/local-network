#!/usr/bin/env bash

set -e
set -x

########################################################################
# Configuration

GATEWAY_SOURCES=/path/to/local/gateway/repo
GATEWAY_LOG_LEVEL=trace

# Local Postgres
GATEWAY_POSTGRES_USERNAME=

# Get these from Jannis or Martynas
GATEWAY_MNEMONIC=
GATEWAY_STUDIO_DATABASE_PASSWORD=
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

# Ensure a local gateway database exists
(createdb gateway 2>/dev/null || true)

cd $GATEWAY_SOURCES

pushd packages/query-engine
yarn
popd

pushd packages/gateway

yarn agent \
  --name gateway-local \
  --metrics-port 7302 \
  --gateway http://localhost:6700/ \
  --gateway-postgres gateway \
  --ethereum-networks mainnet:15:https://eth-mainnet.alchemyapi.io/v2/mWSH9YlhpXfXymzLxptC1TE2CIy2QuMA \
  --sync-allocations-interval 10000 \
  --minimum-indexer-version 0.15.0 \
  --studio-database-port 5433 \
  --studio-database-database subgraph-studio \
  --studio-database-username subgraph-studio \
  | tee /tmp/gateway-agent.log
