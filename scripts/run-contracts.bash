#!/usr/bin/env bash
source prelude.bash

export NODE_ENV=development

cd projects/graphprotocol/contracts
yarn deploy-ganache-manual

STAKING_CONTRACT_ADDRESS=$(jq '."1337".Staking.address' addresses.json)
GNS_CONTRACT_ADDRESS=$(jq '."1337".GNS.address' addresses.json)

# Set short epoch length interval
ts-node ./cli/cli.ts protocol set epochs-length 4
# Set subgraph availability oracle EOA
ts-node ./cli/cli.ts protocol set subgraph-availability-oracle "${ACCOUNT2_ADDRESS}"
# Unpause network
./cli/cli.ts protocol set controller-set-paused 0
# Approve staking contract
./cli/cli.ts contracts graphToken approve \
  --mnemonic "${MNEMONIC}" \
  --provider-url "${ETHEREUM}" \
  --account "${STAKING_CONTRACT_ADDRESS}" \
  --amount 1000000
# Stake
./cli/cli.ts contracts staking stake \
  --mnemonic "${MNEMONIC}" \
  --provider-url "${ETHEREUM}" \
  --amount 1000000
# Publish subgraph to the network
./cli/cli.ts contracts gns publishNewSubgraph \
  --mnemonic "${MNEMONIC}" \
  --provider-url "${ETHEREUM}" \
  --ipfs "${IPFS}" \
  --subgraphDeploymentID "${NETWORK_SUBGRAPH_DEPLOYMENT}" \
  --subgraphPath '/subgraphMetadata.json' \
  --versionPath '/versionMetadata.json'
# Approve GNS contract
./cli/cli.ts contracts graphToken approve \
  --mnemonic "${MNEMONIC}" \
  --provider-url "${ETHEREUM}" \
  --account "${GNS_CONTRACT_ADDRESS}" \
  --amount 1000000
# Mint and signal on subgraph
./cli/cli.ts contracts gns mintSignal \
  --subgraphID "${NETWORK_SUBGRAPH_ID_0}" \
  --tokens 1000

bash ./scripts/check-contracts.bash
