#!/bin/sh
set -eu
. /opt/.env

# don't rerun when retriggered via a service_completed_successfully condition
if curl -s http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { deployment } }" }' | \
  grep "_meta"
then
  exit 0
fi

# Initialize address books
cd /opt/contracts/packages
cd horizon && echo "{}" > addresses-local-network.json && cd ..
cd subgraph-service && echo "{}" > addresses-local-network.json && cd ..

# == DEPLOY PROTOCOL WITH SUBGRAPH SERVICE ==
if [ -n "${FORK_RPC_URL:-}" ]; then
  # TODO: remove this after horizon. This is only useful for testing the ugprade.
  echo "FORK_RPC_URL detected, upgrading current version of the protocol"
  cd /opt/contracts/packages

  # Transfer ownership of protocol to hardhat signer 1
  cd horizon && npx hardhat test:transfer-ownership --network localNetwork && cd ..

  # Now we can upgrade the protocol
  cd horizon && npx hardhat deploy:migrate --network localNetwork --step 1 && cd ..
  cd subgraph-service && npx hardhat deploy:migrate --network localNetwork --step 1 && cd ..
  cd horizon && npx hardhat deploy:migrate --network localNetwork --step 2 --patch-config --account-index 1 && cd ..
  cd horizon && npx hardhat deploy:migrate --network localNetwork --step 3 --patch-config && cd ..
  cd subgraph-service && npx hardhat deploy:migrate --network localNetwork --step 2 --patch-config && cd ..
  cd horizon && npx hardhat deploy:migrate --network localNetwork --step 4 --patch-config --account-index 1 && cd ..
else
  echo "No FORK_RPC_URL detected, deploying new version of the protocol"
  cd /opt/contracts/packages/subgraph-service
  npx hardhat deploy:protocol --network localNetwork --subgraph-service-config localNetwork
fi

# == DEPLOY NETWORK SUBGRAPH ==
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

# Keep the container running - for development purposes
if [ -n "${KEEP_CONTAINER_RUNNING:-}" ]; then
  tail -f /dev/null
fi