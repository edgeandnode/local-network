#!/bin/sh
set -eu
. /opt/.env

# don't rerun when retriggered via a service_completed_successfully condition
if curl http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { deployment } }" }' | \
  grep "_meta"
then
  exit 0
fi

cd /opt/contracts/packages/contracts
echo "{}" > addresses-local.json
sed -i "s/127.0.0.1:${CHAIN_RPC}/chain:${CHAIN_RPC}/g" hardhat.config.ts
sed -i "s/\&governor.*$/\&governor \"${ACCOUNT0_ADDRESS}\"/g" config/graph.localhost.yml
sed -i "s/\&authority.*$/\&authority \"${ACCOUNT0_ADDRESS}\"/g" config/graph.localhost.yml
sed -i "s/myth like bonus scare over problem client lizard pioneer submit female collect/${MNEMONIC}/g" hardhat.config.ts
yarn deploy-localhost

cat addresses-local.json
test "$(jq '."1337".Controller.address' /opt/contracts.json)" = "$(jq '."1337".Controller.address' addresses-local.json)"
test "$(jq '."1337".EpochManager.address' /opt/contracts.json)" = "$(jq '."1337".EpochManager.address' addresses-local.json)"
test "$(jq '."1337".GraphToken.address' /opt/contracts.json)" = "$(jq '."1337".GraphToken.address' addresses-local.json)"
test "$(jq '."1337".DisputeManager.address' /opt/contracts.json)" = "$(jq '."1337".DisputeManager.address' addresses-local.json)"
test "$(jq '."1337".L1Staking.address' /opt/contracts.json)" = "$(jq '."1337".L1Staking.address' addresses-local.json)"
test "$(jq '."1337".StakingExtension.address' /opt/contracts.json)" = "$(jq '."1337".StakingExtension.address' addresses-local.json)"
test "$(jq '."1337".Curation.address' /opt/contracts.json)" = "$(jq '."1337".Curation.address' addresses-local.json)"
test "$(jq '."1337".RewardsManager.address' /opt/contracts.json)" = "$(jq '."1337".RewardsManager.address' addresses-local.json)"
test "$(jq '."1337".ServiceRegistry.address' /opt/contracts.json)" = "$(jq '."1337".ServiceRegistry.address' addresses-local.json)"
test "$(jq '."1337".L1GNS.address' /opt/contracts.json)" = "$(jq '."1337".L1GNS.address' addresses-local.json)"
test "$(jq '."1337".SubgraphNFT.address' /opt/contracts.json)" = "$(jq '."1337".SubgraphNFT.address' addresses-local.json)"
test "$(jq '."1337".L1GraphTokenGateway.address' /opt/contracts.json)" = "$(jq '."1337".L1GraphTokenGateway.address' addresses-local.json)"

printf "\naddresses match"

cd /opt/graph-network-subgraph
sed -i 's/sepolia/hardhat/g' ./config/sepoliaAddressScript.ts
sed -i 's/11155111/1337/g' ./config/sepoliaAddressScript.ts
sed -i 's+@graphprotocol/contracts/addresses.json+/opt/contracts.json+g' ./config/sepoliaAddressScript.ts
sed -i 's/4454000/1/g' ./config/sepoliaAddressScript.ts
npx ts-node config/sepoliaAddressScript.ts
npx mustache ./config/generatedAddresses.json ./config/addresses.template.ts > ./config/addresses.ts
npx mustache ./config/generatedAddresses.json subgraph.template.yaml > subgraph.yaml
npx graph codegen --output-dir src/types/
npx graph create graph-network --node="http://graph-node:${GRAPH_NODE_ADMIN}"
npx graph deploy graph-network --node="http://graph-node:${GRAPH_NODE_ADMIN}" --ipfs="http://ipfs:${IPFS_RPC}" --version-label=v0.0.1
