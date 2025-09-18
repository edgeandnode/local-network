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

# Initialize address books
cd /opt/contracts/packages
cd horizon && echo "{}" > addresses-local-network.json && cd ..
cd subgraph-service && echo "{}" > addresses-local-network.json && cd ..

# == DEPLOY PROTOCOL WITH SUBGRAPH SERVICE ==
echo "No FORK_RPC_URL detected, deploying new version of the protocol"
cd /opt/contracts/packages/subgraph-service
npx hardhat deploy:protocol --network localNetwork --subgraph-service-config localNetwork

# == DEPLOY NETWORK SUBGRAPH ==
cp /opt/contracts/packages/horizon/addresses-local-network.json /opt/horizon.json
cp /opt/contracts/packages/subgraph-service/addresses-local-network.json /opt/subgraph-service.json
cd /opt/graph-network-subgraph

# Patch subgraph service address book, add "legacy" contracts to avoid network subgraph from crashing
jq '.["1337"] += {
  "LegacyServiceRegistry": { "address": "0x0000000000000000000000000000000000000000" },
  "LegacyDisputeManager": { "address": "0x0000000000000000000000000000000000000000" }
}' /opt/subgraph-service.json > /opt/tmp.json && mv /opt/tmp.json /opt/subgraph-service.json

# Build and deploy the subgraph
npx ts-node config/localNetworkAddressScript.ts
npx mustache ./config/generatedAddresses.json ./config/addresses.template.ts > ./config/addresses.ts
npx mustache ./config/generatedAddresses.json subgraph.template.yaml > subgraph.yaml
echo -e "\n== Subgraph manifest ==\n"
cat subgraph.yaml
npx graph codegen --output-dir src/types/
npx graph create graph-network --node="http://graph-node:${GRAPH_NODE_ADMIN}"
npx graph deploy graph-network --node="http://graph-node:${GRAPH_NODE_ADMIN}" --ipfs="http://ipfs:${IPFS_RPC}" --version-label=v0.0.1

# Keep the container running - for development purposes
if [ -n "${KEEP_CONTAINER_RUNNING:-}" ]; then
  tail -f /dev/null
fi