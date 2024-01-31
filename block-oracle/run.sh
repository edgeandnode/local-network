#!/bin/sh
set -euf

if [ ! -d "build/graphprotocol/block-oracle" ]; then
  mkdir -p build/graphprotocol/block-oracle
  git clone git@github.com:graphprotocol/block-oracle build/graphprotocol/block-oracle --branch 'main'
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
dynamic_host_setup graph-node
dynamic_host_setup chain
dynamic_host_setup ipfs

until curl -s "http://${CONTROLLER_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done

echo "awaiting graph-node"
until curl -s "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_STATUS}" >/dev/null; do sleep 1; done
echo "awaiting graph_contracts"
epoch_manager="$(curl "http://${CONTROLLER_HOST}:${CONTROLLER}/graph_contracts" | jq -r '."1337".EpochManager.address')"

cd build/graphprotocol/block-oracle/packages/contracts

sed -i "s+http://localhost:8545+http://${CHAIN_HOST}:${CHAIN_RPC}+g" hardhat.config.ts
yarn
npx hardhat --show-stack-traces run --network ganache scripts/deploy-local.ts | tee deploy.txt
data_edge="$(grep 'contract: ' deploy.txt | awk '{print $3}')"
echo "data_edge=${data_edge}"

cast send "--rpc-url=http://${CHAIN_HOST}:${CHAIN_RPC}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
  "${data_edge}" \
  '0xa1dce3320000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000f030103176569703135353a313333370000000000000000000000000000000000'

cd ../subgraph

yarn
tmp="$(jq <config/local.json ".epochManager |= \"${epoch_manager}\"")" && echo "${tmp}" >config/local.json
yq -i ".hardhat.DataEdge.address |= \"${data_edge}\"" networks.json
yarn prepare
yarn prep:local
yarn codegen
npx graph build --network hardhat
npx graph create block-oracle \
  --node "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_ADMIN}"
npx graph deploy block-oracle \
  --ipfs "http://${IPFS_HOST}:${IPFS_RPC}" \
  --node "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_ADMIN}" \
  --version-label 'v0.0.1' | \
  tee deploy.txt

deployment_id="$(grep "Build completed: " deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"
curl "http://${CONTROLLER_HOST}:${CONTROLLER}/block_oracle_subgraph" -d "${deployment_id}"

curl "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_ADMIN}" \
  -H 'content-type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"subgraph_reassign\",\"params\":{\"node_id\":\"default\",\"ipfs_hash\":\"${deployment_id}\"}}"

cd ../../

export BLOCK_ORACLE_OWNER_ADDRESS="${ACCOUNT0_ADDRESS#0x}"
export BLOCK_ORACLE_OWNER_SECRET_KEY="${ACCOUNT0_SECRET_KEY#0x}"
export DATA_EDGE_CONTRACT_ADDRESS="${data_edge#0x}"
export EPOCH_MANAGER_CONTRACT_ADDRESS="${epoch_manager#0x}"
export SUBGRAPH_URL="http://${GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL}/subgraphs/name/block-oracle"
export PROTOCOL_CHAIN_JRPC_URL="http://${CHAIN_HOST}:${CHAIN_RPC}"
envsubst <../../../block-oracle/config.toml >config.toml
cat config.toml
export RUST_BACKTRACE='1'
export RUST_LOG=debug
sleep 5 # avoid indexing delay causing a long retry delay immediately
cargo run -p block-oracle -- run config.toml
