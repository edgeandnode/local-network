#!/bin/sh
set -eu
. /opt/.env

cd /opt/block-oracle/packages/contracts
sed -i "s/localhost/chain/g" hardhat.config.ts
sed -i "s/'myth like bonus scare over problem client lizard pioneer submit female collect'/'${MNEMONIC}'/g" hardhat.config.ts
yarn
npx hardhat run --network ganache scripts/deploy-local.ts | tee deploy.txt
data_edge="$(grep 'contract: ' deploy.txt | awk '{print $3}')"
# [ { "add": ["eip155:1337"], "message": "RegisterNetworks", "remove": [] } ]
cast send --rpc-url="http://chain:${CHAIN_RPC}" --confirmations=0 --mnemonic="${MNEMONIC}" \
  "${data_edge}" \
  '0xa1dce3320000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000f030103176569703135353a313333370000000000000000000000000000000000'

cd ../subgraph
yarn
graph_epoch_manager="$(jq -r '."1337".EpochManager.address' /opt/graph-contracts.json)"
yq -i ".epochManager |= \"${graph_epoch_manager}\"" config/local.json
yq -i ".permissionList[0].address |= \"0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266\"" config/local.json
cat config/local.json
yq -i ".hardhat.DataEdge.address |= \"${data_edge}\"" networks.json
yarn prepare
yarn prep:local
yarn codegen
npx graph build --network hardhat
yq -i ".dataSources[0].network |= \"local\"" subgraph.yaml
cat subgraph.yaml
npx graph create block-oracle --node="http://graph-node:${GRAPH_NODE_ADMIN}"
npx graph deploy block-oracle --node="http://graph-node:${GRAPH_NODE_ADMIN}" --ipfs="http://ipfs:${IPFS_RPC}" --version-label 'v0.0.1' | tee deploy.txt
deployment_id="$(grep "Build completed: " deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"
echo "${deployment_id}"
curl "http://graph-node:${GRAPH_NODE_ADMIN}" \
  -H 'content-type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"subgraph_reassign\",\"params\":{\"node_id\":\"default\",\"ipfs_hash\":\"${deployment_id}\"}}" && \
  echo ""

cd ../..
export BLOCK_ORACLE_OWNER_ADDRESS="90F8bf6A479f320ead074411a4B0e7944Ea8c9C1"
export BLOCK_ORACLE_OWNER_SECRET_KEY="4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d"
export DATA_EDGE_CONTRACT_ADDRESS="${data_edge#0x}"
export EPOCH_MANAGER_CONTRACT_ADDRESS="${graph_epoch_manager#0x}"
export SUBGRAPH_URL="http://graph-node:8000/subgraphs/name/block-oracle"
export PROTOCOL_CHAIN_JRPC_URL="http://chain:8545"
envsubst </opt/config.toml >config.toml
cat config.toml
sleep 5 # avoid indexing delay causing a long retry delay immediately
/opt/block-oracle/block-oracle run config.toml
