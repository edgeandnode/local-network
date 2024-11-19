#!/bin/sh
set -eu
. /opt/.env

cd /opt/contracts/packages/data-edge
sed -i "s/localhost/chain/g" hardhat.config.ts
export MNEMONIC="${MNEMONIC}"
yarn
cat hardhat.config.ts
yarn build
npx hardhat data-edge:deploy --contract EventfulDataEdge --deploy-name EBO --network ganache | tee deploy.txt
data_edge="$(grep 'contract: ' deploy.txt | awk '{print $3}')"
# [ { "add": ["eip155:1337"], "message": "RegisterNetworks", "remove": [] } ]
cast send --rpc-url="http://chain:${CHAIN_RPC}" --confirmations=0 --mnemonic="${MNEMONIC}" \
  "${data_edge}" \
  '0xa1dce3320000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000f030103176569703135353a313333370000000000000000000000000000000000'

cd /opt/block-oracle/packages/subgraph
yarn
graph_epoch_manager="$(jq -r '."1337".EpochManager.address' /opt/contracts.json)"
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
cat >config.toml <<-EOF
blockmeta_auth_token = ""
owner_address = "90F8bf6A479f320ead074411a4B0e7944Ea8c9C1"
owner_private_key = "4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d"
data_edge_address = "${data_edge#0x}"
epoch_manager_address = "${graph_epoch_manager#0x}"
subgraph_url = "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/block-oracle"
bearer_token = "TODO"
log_level = "trace"

[protocol_chain]
name = "eip155:1337"
jrpc = "http://chain:8545"
polling_interval_in_seconds = 20

[indexed_chains]
"eip155:1337" = "http://chain:8545"
EOF
cat config.toml
sleep 5 # avoid indexing delay causing a long retry delay immediately
/opt/block-oracle/block-oracle run config.toml
