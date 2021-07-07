#!/usr/bin/env bash

set -e

########################################################################
# Configuration

export GATEWAY_SOURCES=/path/to/gateway
export GATEWAY_LOG_LEVEL=trace

# Local Postgres
export GATEWAY_POSTGRES_USERNAME=

# Get these from Jannis or Martynas
export GATEWAY_MNEMONIC=
export GATEWAY_STUDIO_DATABASE_PASSWORD=
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
  --postgres-database gateway \
  --ethereum-networks mainnet:15:https://eth-mainnet.alchemyapi.io/v2/mWSH9YlhpXfXymzLxptC1TE2CIy2QuMA \
  --sync-allocations-interval 10000 \
  --minimum-indexer-version 0.15.0 \
  --studio-database-port 5433 \
  --studio-database-database subgraph-studio \
  --studio-database-username subgraph-studio \
  | tee /tmp/gateway-agent.log
