#!/bin/sh
set -eu
. /opt/.env

# don't rerun when retriggered via a service_completed_successfully condition
# but also check if contracts are actually deployed on the current chain
if curl -s http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { deployment } }" }' | \
  grep "_meta"
then
  # Additional check: verify contracts are actually deployed on current chain
  if [ -f "/opt/contracts/packages/horizon/addresses-local-network.json" ]; then
    l2_graph_token=$(jq -r '.["1337"].L2GraphToken.address // empty' /opt/contracts/packages/horizon/addresses-local-network.json)
    if [ -n "$l2_graph_token" ]; then
      # Check if the contract actually has code on the current chain
      code_check=$(cast code --rpc-url="http://chain:${CHAIN_RPC}" "$l2_graph_token" 2>/dev/null || echo "0x")
      if [ "$code_check" = "0x" ]; then
        echo "Contract addresses in horizon.json are stale (no code at $l2_graph_token), redeploying..."
      else
        echo "Contracts already deployed and graph-network subgraph exists, skipping..."
        exit 0
      fi
    fi
  else
    echo "addresses-local-network.json not found, proceeding with deployment..."
  fi
fi

# Deploy legacy protocol
echo "Deploying legacy protocol..."
cd /opt
git clone https://github.com/graphprotocol/contracts contracts-legacy
cd contracts-legacy
git checkout ${LEGACY_CONTRACTS_COMMIT}
cd packages/contracts && yarn && yarn compile 

echo "{}" > addresses-local.json
sed -i "s/127.0.0.1:${CHAIN_RPC}/chain:${CHAIN_RPC}/g" hardhat.config.ts
sed -i "s/\&governor.*$/\&governor \"${ACCOUNT0_ADDRESS}\"/g" config/graph.localhost.yml
sed -i "s/\&authority.*$/\&authority \"${ACCOUNT0_ADDRESS}\"/g" config/graph.localhost.yml
sed -i "s/myth like bonus scare over problem client lizard pioneer submit female collect/${MNEMONIC}/g" hardhat.config.ts
yarn deploy-localhost

# Upgrade protocol
echo "Upgrading protocol to Phase 3..."
cd /opt/contracts/packages
cd horizon && echo "{}" > addresses-local-network.json && cd ..
cd subgraph-service && echo "{}" > addresses-local-network.json && cd ..

# Now we can upgrade the protocol up to Phase 3
cd horizon && npx hardhat deploy:migrate --network localNetwork --step 1 && cd ..
cd subgraph-service && npx hardhat deploy:migrate --network localNetwork --step 1 && cd ..
cd horizon && npx hardhat deploy:migrate --network localNetwork --step 2 --patch-config && cd ..
cd horizon && npx hardhat deploy:migrate --network localNetwork --step 3 --patch-config && cd ..
cd subgraph-service && npx hardhat deploy:migrate --network localNetwork --step 2 --patch-config && cd ..

# To complete the upgrade the following step can be manually run on the graph-contracts container:
# cd horizon && npx hardhat deploy:migrate --network localNetwork --step 4 --patch-config && cd ..

# == DEPLOY NETWORK SUBGRAPH ==
echo "Deploying network subgraph..."
cp /opt/contracts/packages/horizon/addresses-local-network.json /opt/horizon.json
cp /opt/contracts/packages/subgraph-service/addresses-local-network.json /opt/subgraph-service.json
cd /opt/graph-network-subgraph

# Build and deploy the subgraph
npx ts-node config/localNetworkAddressScript.ts
npx mustache ./config/generatedAddresses.json ./config/addresses.template.ts > ./config/addresses.ts
npx mustache ./config/generatedAddresses.json subgraph.template.yaml > subgraph.yaml
npx graph codegen --output-dir src/types/
npx graph create graph-network --node="http://graph-node:${GRAPH_NODE_ADMIN}"
npx graph deploy graph-network --node="http://graph-node:${GRAPH_NODE_ADMIN}" --ipfs="http://ipfs:${IPFS_RPC}" --version-label=v0.0.1

cat subgraph.yaml

# Keep the container running - for development purposes
if [ -n "${KEEP_CONTAINER_RUNNING:-}" ]; then
  tail -f /dev/null
fi