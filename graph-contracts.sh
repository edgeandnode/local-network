#!/bin/sh
. ./prelude.sh

await "curl -sf localhost:${ETHEREUM_PORT} > /dev/null"

cd build/graphprotocol/contracts

yarn deploy-localhost --skip-confirmation

if [ "$(uname)" != Darwin ]; then
  find_replace_sed '_src\/\*.ts' '_src\/types\/\*.ts' scripts/prepublish
fi

yarn run prepublishOnly

yalc push

staking_contract=$(jq -r '."1337".Staking.address' addresses.json)
gns_contract=$(jq -r '."1337".GNS.address' addresses.json)
allocation_exchange_contract=$(jq -r '."1337".AllocationExchange.address' addresses.json)

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
  --mnemonic "${MNEMONIC}" \
  --subgraphID "${NETWORK_SUBGRAPH_ID_0}" \
  --tokens 1000
# Fund AllocationExchange
./cli/cli.ts contracts graphToken mint \
  --mnemonic "${MNEMONIC}" \
  --account "${allocation_exchange_contract}" \
  --amount 1000000

cd -

signal_ready graph-contracts
