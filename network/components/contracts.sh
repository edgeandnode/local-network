#!/usr/bin/env bash

set -e

########################################################################
# Configuration

export ADDRESS_BOOK=$CONTRACTS_SOURCES/addresses.json
export GRAPH_CONFIG=CONTRACTS_SOURCES/graph.config.yml

export PROVIDER_URL=$ETHEREUM

########################################################################
# Run

export NODE_ENV=development

cd $CONTRACTS_SOURCES

export STAKING_CONTRACT_ADDRESS=$(jq '."1337".Staking.address' $ADDRESS_BOOK)
export GNS_CONTRACT_ADDRESS=$(jq '."1337".GNS.address' $ADDRESS_BOOK)

# Install project dependencies and build contract artifacts
yarn
yarn build

# Deploy contracts to local test network
yarn deploy-ganache-manual

# Publish so the other components have access to the address book
yalc publish

# Set short epoch length interval
ts-node ./cli/cli.ts protocol set epochs-length 4;

# Set subgraph availability oracle EOA
ts-node ./cli/cli.ts protocol set subgraph-availability-oracle $ACCOUNT2_ADDRESS;

# Unpause network
./cli/cli.ts protocol set controller-set-paused 0

# Approve staking contract
./cli/cli.ts contracts graphToken approve \
  --mnemonic "$MNEMONIC" \
  --provider-url "$ETHEREUM" \
  --account "$STAKING_CONTRACT_ADDRESS" \
  --amount 1000000

# Stake
./cli/cli.ts contracts staking stake \
  --mnemonic "$MNEMONIC" \
  --provider-url "$ETHEREUM" \
  --amount 1000000

# Publish subgraph to the network
./cli/cli.ts contracts gns publishNewSubgraph \
  --mnemonic "$MNEMONIC" \
  --provider-url "$ETHEREUM" \
  --ipfs "$IPFS" \
  --graphAccount "$ACCOUNT_ADDRESS" \
  --subgraphDeploymentID QmcUrDscqmmf3FAHNyGW8kJM6ZBp62mgFrJNFJFPkPzNEy \
  --subgraphPath '/subgraphMetadata.json' \
  --versionPath '/versionMetadata.json'

# Approve GNS contract
./cli/cli.ts contracts graphToken approve \
  --mnemonic "$MNEMONIC" \
  --provider-url "$ETHEREUM" \
  --account "$GNS_CONTRACT_ADDRESS" \
  --amount 1000000

# Mint and signal on subgraph
./cli/cli.ts contracts gns mintNSignal \
  --graphAccount "$ACCOUNT_ADDRESS" \
  --tokens 1000 \
  --subgraphNumber 0
