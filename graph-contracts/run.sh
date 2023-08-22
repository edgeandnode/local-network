#!/bin/sh
set -euf

if [ ! -d "build/graphprotocol/contracts" ]; then
    mkdir -p build/graphprotocol/contracts
    git clone git@github.com:graphprotocol/contracts build/graphprotocol/contracts --branch 'v3.0.0'
fi
if [ ! -d "build/graphprotocol/graph-network-subgraph" ]; then
    mkdir -p build/graphprotocol/graph-network-subgraph
    git clone git@github.com:graphprotocol/graph-network-subgraph build/graphprotocol/graph-network-subgraph --branch 'master'
fi

. ./.env
host="${DOCKER_GATEWAY_HOST:-host.docker.internal}"

cd build/graphprotocol/contracts

yarn
yarn add graceful-fs # fixes a strange lockfile issue
sed -i "s+http://localhost:8545+http://${host}:${CHAIN_RPC}+g" hardhat.config.ts
yarn deploy --force --skip-confirmation --network localhost --graph-config config/graph.localhost.yml

npx ts-node ./cli/cli.ts protocol set epochs-length 4 \
    --provider-url "http://${host}:${CHAIN_RPC}"
npx ts-node ./cli/cli.ts protocol set subgraph-availability-oracle "${SAO_ADDRESS}" \
    --provider-url "http://${host}:${CHAIN_RPC}"
npx ts-node ./cli/cli.ts protocol set controller-set-paused 0 \
    --provider-url "http://${host}:${CHAIN_RPC}"
npx ts-node ./cli/cli.ts contracts graphToken approve \
  --provider-url "http://${host}:${CHAIN_RPC}" \
  --mnemonic "${ACCOUNT0_MNEMONIC}" \
  --account "$(jq -r '."1337".Staking.address' addresses.json)" \
  --amount 1000000
npx ts-node ./cli/cli.ts contracts graphToken approve \
  --provider-url "http://${host}:${CHAIN_RPC}" \
  --mnemonic "${ACCOUNT0_MNEMONIC}" \
  --account "$(jq -r '."1337".GNS.address' addresses.json)" \
  --amount 1000000
npx ts-node ./cli/cli.ts contracts staking stake \
  --provider-url "http://${host}:${CHAIN_RPC}" \
  --mnemonic "${ACCOUNT0_MNEMONIC}" \
  --amount 1000000

cd ../graph-network-subgraph

yarn

npx graph create graph-network \
  --node "http://${host}:${GRAPH_NODE_ADMIN}"
yarn prep:no-ipfs

yarn add --dev ts-node
cp ../../../graph-contracts/hardhatAddressScript.ts config/
npx ts-node config/hardhatAddressScript.ts
npx mustache ./config/generatedAddresses.json ./config/addresses.template.ts > ./config/addresses.ts

npx mustache ./config/generatedAddresses.json subgraph.template.yaml > subgraph.yaml
npx graph codegen --output-dir src/types/

npx graph deploy graph-network \
  --ipfs "http://${host}:${IPFS_RPC}" \
  --node "http://${host}:${GRAPH_NODE_ADMIN}" \
  --version-label "$(jq .label ../../../graph-contracts/versionMetadata.json)" | \
  tee deploy.txt

deployment_id="$(grep "Build completed: " deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"

cd ../contracts

npx ts-node ./cli/cli.ts contracts gns publishNewSubgraph \
  --mnemonic "${ACCOUNT0_MNEMONIC}" \
  --provider-url "http://${host}:${CHAIN_RPC}" \
  --ipfs "http://${host}:${IPFS_RPC}/" \
  --subgraphDeploymentID "${deployment_id}" \
  --subgraphPath '../../../../graph-contracts/subgraphMetadata.json' \
  --versionPath '../../../../graph-contracts/versionMetadata.json'

subgraph_id=null
while [ "${subgraph_id}" = "null" ]; do
  subgraph_id=$(curl -s "http://${host}:${GRAPH_NODE_GRAPHQL}/subgraphs/id/${deployment_id}" \
    -H 'content-type: application/json' \
    -d "{\"query\": \"{subgraphDeployments(where:{ipfsHash:\\\"${deployment_id}\\\"}) {versions { subgraph { id } } } }\"}" \
    | jq -r '.data.subgraphDeployments[0].versions[0].subgraph.id')
  echo "subgraph_id=${subgraph_id}"
done

subgraph_id_hex=$(npx ts-node -e "import {utils} from 'ethers'; console.log(utils.hexlify(utils.base58.decode(\"${subgraph_id}\")))")
echo "subgraph_id_hex=${subgraph_id_hex}"

npx ts-node ./cli/cli.ts contracts gns mintSignal \
  --provider-url "http://${host}:${CHAIN_RPC}" \
  --mnemonic "${ACCOUNT0_MNEMONIC}" \
  --subgraphID "${subgraph_id_hex}" \
  --tokens 1000

# TODO: why's this failing?
# npx ts-node ./cli/cli.ts contracts graphToken mint \
#   --provider-url "http://${host}:${CHAIN_RPC}" \
#   --mnemonic "${ACCOUNT0_MNEMONIC}" \
#   --account "$(jq -r '."1337".AllocationExchange.address' addresses.json)" \
#   --amount 1000000

epoch_manager="$(jq -r '."1337".EpochManager.address' addresses.json)"
curl "http://${host}:${CONTROLLER}/graph_epoch_manager" -d "${epoch_manager}"
curl "http://${host}:${CONTROLLER}/graph_subgraph" -d "${subgraph_id}"
curl "http://${host}:${CONTROLLER}/graph_subgraph_deployment" -d "${deployment_id}"

# The Docker compose service_completed_successfully condition results in restarts every time a
# dependent service is modified. That's too annoying so I just run a dummy server instead for a
# service_healthy condition.
yarn add --dev http-server
npx http-server --silent
