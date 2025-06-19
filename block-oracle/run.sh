#!/bin/bash
set -eu
. /opt/.env

cd /opt/contracts/packages/data-edge
sed -i "s/localhost/chain/g" hardhat.config.ts
export MNEMONIC="${MNEMONIC}"
pnpm install
echo "hardhat.config.ts"
sed -i "s/myth like bonus scare over problem client lizard pioneer submit female collect/${MNEMONIC}/g" hardhat.config.ts
cat hardhat.config.ts
pnpm build
npx hardhat data-edge:deploy --contract EventfulDataEdge --deploy-name EBO --network ganache | tee deploy.txt
data_edge="$(grep 'contract: ' deploy.txt | awk '{print $3}')"

# https://graphprotocol.github.io/block-oracle/
# [ { "add": ["eip155:1337"], "message": "RegisterNetworks", "remove": [] } ]
output=$(cast send --rpc-url="http://chain:${CHAIN_RPC}" --confirmations=0 --mnemonic="${MNEMONIC}" \
  "${data_edge}" \
  '0xa1dce3320000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000f030103176569703135353a313333370000000000000000000000000000000000' 2>&1)

exit_code=$?

if [ $exit_code -ne 0 ]; then
  echo "Error during cast send: $output" | tee -a error.log
else
  echo "$output"
fi

cd /opt/block-oracle/packages/subgraph
pnpm install
graph_epoch_manager="$(jq -r '."1337".EpochManager.address' /opt/contracts.json)"
yq -i ".epochManager |= \"${graph_epoch_manager}\"" config/local.json
yq -i ".permissionList[0].address |= \"0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266\"" config/local.json
cat config/local.json
yq -i ".hardhat.DataEdge.address |= \"${data_edge}\"" networks.json
echo "networks.json"
cat networks.json
pnpm prepare
pnpm prep:local
pnpm codegen
npx graph build --network hardhat
yq -i ".dataSources[0].network |= \"hardhat\"" subgraph.yaml
cat subgraph.yaml
npx graph create block-oracle --node="http://graph-node:${GRAPH_NODE_ADMIN}"
npx graph deploy block-oracle --node="http://graph-node:${GRAPH_NODE_ADMIN}" --ipfs="http://ipfs:${IPFS_RPC}" --version-label 'v0.0.1' | tee deploy.txt
deployment_id="$(grep "Build completed: " deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"
echo "deployed block-oracle to deployment_id: ${deployment_id}"
curl -s "http://graph-node:${GRAPH_NODE_ADMIN}" \
  -H 'content-type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"subgraph_reassign\",\"params\":{\"node_id\":\"default\",\"ipfs_hash\":\"${deployment_id}\"}}" && \
  echo ""

cd ../..
cat >config.toml <<-EOF
blockmeta_auth_token = ""
owner_address = "${ACCOUNT0_ADDRESS#0x}"
owner_private_key = "${ACCOUNT0_SECRET#0x}"
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
echo "generated config.toml"
cat config.toml
sleep 5 # avoid indexing delay causing a long retry delay immediately
/opt/block-oracle/block-oracle run config.toml
