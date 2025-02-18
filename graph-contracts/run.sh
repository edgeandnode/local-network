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

# == DEPLOY PROTOCOL WITH SUBGRAPH SERVICE ==
export SECURE_ACCOUNTS_DISABLE_PROVIDER=true
export HARDHAT_VAR_LOCALHOST_RPC=http://chain:8545
export HARDHAT_VAR_LOCALHOST_CHAIN_ID=1337

cd /opt/contracts/packages/subgraph-service
jq --arg governor "$ACCOUNT0_ADDRESS" \
   '.["$global"].governor = $governor' \
   "/opt/contracts/packages/subgraph-service/ignition/configs/subgraph-service.default.json5" \
   > temp.json && \
   mv temp.json "/opt/contracts/packages/subgraph-service/ignition/configs/subgraph-service.default.json5"
npx hardhat deploy:protocol --network localhost

# TODO: add back this assertion section once the deployment is stable
# cat addresses-local.json
# test "$(jq '."1337".Controller.address' /opt/contracts.json)" = "$(jq '."1337".Controller.address' addresses-local.json)"
# test "$(jq '."1337".EpochManager.address' /opt/contracts.json)" = "$(jq '."1337".EpochManager.address' addresses-local.json)"
# test "$(jq '."1337".GraphToken.address' /opt/contracts.json)" = "$(jq '."1337".GraphToken.address' addresses-local.json)"
# test "$(jq '."1337".DisputeManager.address' /opt/contracts.json)" = "$(jq '."1337".DisputeManager.address' addresses-local.json)"
# test "$(jq '."1337".L1Staking.address' /opt/contracts.json)" = "$(jq '."1337".L1Staking.address' addresses-local.json)"
# test "$(jq '."1337".StakingExtension.address' /opt/contracts.json)" = "$(jq '."1337".StakingExtension.address' addresses-local.json)"
# test "$(jq '."1337".Curation.address' /opt/contracts.json)" = "$(jq '."1337".Curation.address' addresses-local.json)"
# test "$(jq '."1337".RewardsManager.address' /opt/contracts.json)" = "$(jq '."1337".RewardsManager.address' addresses-local.json)"
# test "$(jq '."1337".ServiceRegistry.address' /opt/contracts.json)" = "$(jq '."1337".ServiceRegistry.address' addresses-local.json)"
# test "$(jq '."1337".L1GNS.address' /opt/contracts.json)" = "$(jq '."1337".L1GNS.address' addresses-local.json)"
# test "$(jq '."1337".SubgraphNFT.address' /opt/contracts.json)" = "$(jq '."1337".SubgraphNFT.address' addresses-local.json)"
# test "$(jq '."1337".L1GraphTokenGateway.address' /opt/contracts.json)" = "$(jq '."1337".L1GraphTokenGateway.address' addresses-local.json)"

# printf "\naddresses match"

# == DEPLOY NETWORK SUBGRAPH ==
# cd /opt/graph-network-subgraph
# sed -i 's/sepolia/hardhat/g' ./config/sepoliaAddressScript.ts
# sed -i 's/11155111/1337/g' ./config/sepoliaAddressScript.ts
# sed -i 's+@graphprotocol/contracts/addresses.json+/opt/contracts.json+g' ./config/sepoliaAddressScript.ts
# sed -i 's/4454000/1/g' ./config/sepoliaAddressScript.ts
# npx ts-node config/sepoliaAddressScript.ts
# npx mustache ./config/generatedAddresses.json ./config/addresses.template.ts > ./config/addresses.ts
# npx mustache ./config/generatedAddresses.json subgraph.template.yaml > subgraph.yaml
# npx graph codegen --output-dir src/types/
# npx graph create graph-network --node="http://graph-node:${GRAPH_NODE_ADMIN}"
# npx graph deploy graph-network --node="http://graph-node:${GRAPH_NODE_ADMIN}" --ipfs="http://ipfs:${IPFS_RPC}" --version-label=v0.0.1
