#!/bin/sh
set -euf

. ./.env

graph_contracts="$(curl -s http://controller:${CONTROLLER}/graph_contracts)"
block_oracle_subgraph="$(curl "http://controller:${CONTROLLER}/block_oracle_subgraph")"

# deterministic subgraph ID for first subgraph created by account 0
subgraph_id="F9NcUmUuzqMCNLFVfHfWP98dUGMFDL2opTdVnB8zFhLc"
subgraph_id_hex="0xd228b32ac4ed94443422ec6ced4a85b81550e87f4e438a9154b616b09cbb3b31"

# create subgraph we can allocate to (EBO, because network subgraph is special for some reason)

cd build/graphprotocol/contracts

export HARDHAT_DISABLE_TELEMETRY_PROMPT=true
yarn && yarn build

echo '{"description":"test","label":"0.0.1"}' >version-metadata.json
echo '{"description":"test","displayName":"test","image":"","codeRepository":"","website":""}' >subgraph-metadata.json
echo "${graph_contracts}" > addresses.json
npx ts-node ./cli/cli.ts contracts gns publishNewSubgraph \
  --address-book addresses.json \
  --mnemonic "${MNEMONIC}" \
  --provider-url "http://chain:${CHAIN_RPC}" \
  --ipfs "http://ipfs:${IPFS_RPC}/" \
  --subgraphDeploymentID "${block_oracle_subgraph}" \
  --subgraphPath '../subgraph-metadata.json' \
  --versionPath '../version-metadata.json'

token_address="$(echo "${graph_contracts}" | jq -r '."1337".GraphToken.address')"
gns_address="$(echo "${graph_contracts}" | jq -r '."1337".L1GNS.address')"
staking_address="$(echo "${graph_contracts}" | jq -r '."1337".L1Staking.address')"
allocation_exchange_address="$(echo "${graph_contracts}" | jq -r '."1337".AllocationExchange.address')"

cast send "--rpc-url=http://chain:${CHAIN_RPC}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
  "${token_address}" 'approve(address,uint256)' "${gns_address}" '1000000000000000000000'
cast send "--rpc-url=http://chain:${CHAIN_RPC}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
  "${gns_address}" 'mintSignal(uint256,uint256,uint256)' "${subgraph_id_hex}" '1000000000000000000000' '1'

cast send "--rpc-url=http://chain:${CHAIN_RPC}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
  "${token_address}" 'approve(address,uint256)' "${staking_address}" '200000000000000000000000'
cast send "--rpc-url=http://chain:${CHAIN_RPC}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
  "${staking_address}" 'stake(uint256)' '200000000000000000000000'

cast send "--rpc-url=http://chain:${CHAIN_RPC}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
  "${token_address}" 'transfer(address,uint256)' "${allocation_exchange_address}" '1000000000000000000000'

# set indexer rules to allocate

cd ../indexer/packages/indexer-cli
yarn
./bin/graph-indexer indexer connect "http://indexer-agent:${INDEXER_MANAGEMENT}"
./bin/graph-indexer --network=hardhat indexer rules set global \
  decisionBasis rules minSignal 0 allocationAmount 1

curl "http://controller:${CONTROLLER}/allocation_subgraph" -d "${subgraph_id}"
