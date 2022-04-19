#!/bin/sh
. ./prelude.sh

await "curl -sf localhost:${ETHEREUM_PORT} > /dev/null"

cd build/graphprotocol/contracts

# TODO: How should we determine the authority address?
find_replace_sed \
  '\&authority "0x79fd74da4c906509862c8fe93e87a9602e370bc4"' \
  '\&authority "0x5d0365e8dcbd1b00fc780b206e85c9d78159a865"' \
  graph.config.yml
cp ../../../subgraphMetadata.json ../../../versionMetadata.json ./cli

yarn --non-interactive
yarn build

npx hardhat migrate

yarn deploy-ganache-manual

find_replace_sed '_src\/\*.ts' '_src\/types\/\*.ts' scripts/prepublish
./scripts/prepublish

yalc push

staking_contract=$(jq '."1337".Staking.address' addresses.json)
gns_contract=$(jq '."1337".GNS.address' addresses.json)
allocation_exchange_contract=$(jq '."1337".AllocationExchange.address' addresses.json)

# Set short epoch length interval
ts-node ./cli/cli.ts protocol set epochs-length 4
# Set subgraph availability oracle EOA
ts-node ./cli/cli.ts protocol set subgraph-availability-oracle "${ACCOUNT2_ADDRESS}"
# Unpause network
./cli/cli.ts protocol set controller-set-paused 0
# Approve staking contract
./cli/cli.ts contracts graphToken approve \
  --mnemonic "${MNEMONIC}" \
  --provider-url "http://localhost:${ETHEREUM_PORT}" \
  --account "${staking_contract}" \
  --amount 1000000
# Stake
./cli/cli.ts contracts staking stake \
  --mnemonic "${MNEMONIC}" \
  --provider-url "http://localhost:${ETHEREUM_PORT}" \
  --amount 1000000
# Publish subgraph to the network
./cli/cli.ts contracts gns publishNewSubgraph \
  --mnemonic "${MNEMONIC}" \
  --provider-url "http://localhost:${ETHEREUM_PORT}" \
  --ipfs "http://localhost:${IPFS_PORT}/" \
  --subgraphDeploymentID "${NETWORK_SUBGRAPH_DEPLOYMENT}" \
  --subgraphPath '/subgraphMetadata.json' \
  --versionPath '/versionMetadata.json'
# Approve GNS contract
./cli/cli.ts contracts graphToken approve \
  --mnemonic "${MNEMONIC}" \
  --provider-url "http://localhost:${ETHEREUM_PORT}" \
  --account "${gns_contract}" \
  --amount 1000000
# Mint and signal on subgraph
./cli/cli.ts contracts gns mintSignal \
  --subgraphID "${NETWORK_SUBGRAPH_ID_0}" \
  --tokens 1000
# Fund AllocationExchange
./cli/cli.ts contracts graphToken mint \
  --account "${allocation_exchange_contract}" \
  --amount 1000000

cd -

signal_ready graph-contracts
