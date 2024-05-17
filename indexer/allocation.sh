#!/bin/sh
set -euf

if [ ! -d "build/graphprotocol/contracts" ]; then
  mkdir -p build/graphprotocol/contracts
  git clone git@github.com:graphprotocol/contracts build/graphprotocol/contracts --branch 'v5.3.0'
fi
if [ ! -d "build/graphprotocol/indexer" ]; then
  mkdir -p build/graphprotocol/indexer
  git clone git@github.com:graphprotocol/indexer build/graphprotocol/indexer --branch 'v0.20.23'
fi

. ./.env

dynamic_host_setup() {
    if [ $# -eq 0 ]; then
        echo "No name provided."
        return 1
    fi

    # Convert the name to uppercase for the variable name
    local name_upper=$(echo $1 | tr '-' '_' | tr '[:lower:]' '[:upper:]')
    local export_name="${name_upper}_HOST"
    local host_name="$1"

    # Directly use 'eval' for dynamic variable assignment to avoid bad substitution
    eval export ${export_name}="${host_name}"
    if ! getent hosts "${host_name}" >/dev/null; then
        eval export ${export_name}="\$DOCKER_GATEWAY_HOST"
    fi

    # Use 'eval' for echoing dynamic variable value
    eval echo "${export_name} is set to \$${export_name}"
}

dynamic_host_setup controller
dynamic_host_setup indexer-agent
dynamic_host_setup ipfs
dynamic_host_setup chain

echo "awaiting controller"
until curl -s "http://${CONTROLLER_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done
# echo "awaiting indexer-service"
# until curl -s "http://${DOCKER_GATEWAY_HOST}:${INDEXER_SERVICE}" >/dev/null; do sleep 1; done
echo "awaiting indexer-agent"
until curl -s "http://${INDEXER_AGENT_HOST}:${INDEXER_MANAGEMENT}" >/dev/null; do sleep 1; done
echo "awaiting graph_contracts"
graph_contracts="$(curl -s http://${CONTROLLER_HOST}:${CONTROLLER}/graph_contracts)"
echo "awaiting block_oracle_subgraph"
block_oracle_subgraph="$(curl "http://${CONTROLLER_HOST}:${CONTROLLER}/block_oracle_subgraph")"
echo "block_oracle_subgraph=${block_oracle_subgraph}"
echo "awaiting escrow subgraph"
escrow_subgraph="$(curl "http://${CONTROLLER_HOST}:${CONTROLLER}/escrow_subgraph")"
echo "escrow_subgraph=${escrow_subgraph}"

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
  --provider-url "http://${CHAIN_HOST}:${CHAIN_RPC}" \
  --ipfs "http://${IPFS_HOST}:${IPFS_RPC}/" \
  --subgraphDeploymentID "${block_oracle_subgraph}" \
  --subgraphPath '../subgraph-metadata.json' \
  --versionPath '../version-metadata.json'

token_address="$(echo "${graph_contracts}" | jq -r '."1337".GraphToken.address')"
gns_address="$(echo "${graph_contracts}" | jq -r '."1337".L1GNS.address')"
staking_address="$(echo "${graph_contracts}" | jq -r '."1337".L1Staking.address')"
allocation_exchange_address="$(echo "${graph_contracts}" | jq -r '."1337".AllocationExchange.address')"

cast send "--rpc-url=http://${CHAIN_HOST}:${CHAIN_RPC}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
  "${token_address}" 'approve(address,uint256)' "${gns_address}" '1000000000000000000000'
cast send "--rpc-url=http://${CHAIN_HOST}:${CHAIN_RPC}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
  "${gns_address}" 'mintSignal(uint256,uint256,uint256)' "${subgraph_id_hex}" '1000000000000000000000' '1'

cast send "--rpc-url=http://${CHAIN_HOST}:${CHAIN_RPC}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
  "${token_address}" 'approve(address,uint256)' "${staking_address}" '200000000000000000000000'
cast send "--rpc-url=http://${CHAIN_HOST}:${CHAIN_RPC}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
  "${staking_address}" 'stake(uint256)' '200000000000000000000000'

cast send "--rpc-url=http://${CHAIN_HOST}:${CHAIN_RPC}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
  "${token_address}" 'transfer(address,uint256)' "${allocation_exchange_address}" '1000000000000000000000'

# set indexer rules to allocate

cd ../indexer/packages/indexer-cli
yarn
./bin/graph-indexer indexer connect "http://${INDEXER_AGENT_HOST}:${INDEXER_MANAGEMENT}"

# allocate towards all published subgraph deployments
./bin/graph-indexer --network=hardhat indexer rules set global \
  decisionBasis rules minSignal 0 allocationAmount 1

# always index the escrow subgraph deployment
./bin/graph-indexer --network=hardhat indexer rules offchain "${escrow_subgraph}"

curl "http://${CONTROLLER_HOST}:${CONTROLLER}/allocation_subgraph" -d "${subgraph_id}"