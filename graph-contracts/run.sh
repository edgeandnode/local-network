#!/bin/sh
set -eu
. /opt/.env

# == HELPER: ENSURE DISPUTE MANAGER REGISTERED IN CONTROLLER ==
# The Horizon DisputeManager is deployed separately from legacy contracts.
# The network subgraph reads DisputeManager from Controller.getContractProxy(keccak256("DisputeManager")).
# Without this registration, attestation verification fails because gateway and indexer-service
# would use different DisputeManager addresses for EIP-712 domain construction.
ensure_dispute_manager_registered() {
  if [ ! -f "/opt/horizon.json" ] || [ ! -f "/opt/subgraph-service.json" ]; then
    echo "Contract address files not found, skipping DisputeManager registration check"
    return
  fi

  controller_address=$(jq -r '.["1337"].Controller.address // empty' /opt/horizon.json)
  dispute_manager_address=$(jq -r '.["1337"].DisputeManager.address // empty' /opt/subgraph-service.json)

  if [ -z "$controller_address" ] || [ -z "$dispute_manager_address" ]; then
    echo "Controller or DisputeManager address not found, skipping registration"
    return
  fi

  dispute_manager_id=$(cast keccak256 "DisputeManager")
  current_proxy=$(cast call --rpc-url="http://chain:${CHAIN_RPC}" \
    "${controller_address}" "getContractProxy(bytes32)(address)" "${dispute_manager_id}" 2>/dev/null || echo "0x")

  # Normalize addresses to lowercase for comparison (cast returns lowercase, JSON may be checksummed)
  current_proxy_lower=$(echo "$current_proxy" | tr '[:upper:]' '[:lower:]')
  dispute_manager_lower=$(echo "$dispute_manager_address" | tr '[:upper:]' '[:lower:]')

  if [ "$current_proxy_lower" = "$dispute_manager_lower" ]; then
    echo "DisputeManager already registered in Controller: ${dispute_manager_address}"
  else
    echo "Registering Horizon DisputeManager in Controller..."
    echo "  Controller: ${controller_address}"
    echo "  DisputeManager: ${dispute_manager_address}"
    echo "  Current proxy: ${current_proxy}"
    # Controller governor is ACCOUNT1 in this deployment
    cast send --rpc-url="http://chain:${CHAIN_RPC}" --confirmations=0 --private-key="${ACCOUNT1_SECRET}" \
      "${controller_address}" "setContractProxy(bytes32,address)" "${dispute_manager_id}" "${dispute_manager_address}"
  fi
}

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
        echo "Contracts already deployed and graph-network subgraph exists"
        # Copy address files so helper can read them
        cp /opt/contracts/packages/horizon/addresses-local-network.json /opt/horizon.json
        cp /opt/contracts/packages/subgraph-service/addresses-local-network.json /opt/subgraph-service.json
        # Ensure DisputeManager is registered (handles upgrades to this version)
        ensure_dispute_manager_registered
        echo "Skipping deployment."
        exit 0
      fi
    fi
  else
    echo "addresses-local-network.json not found, proceeding with deployment..."
  fi
fi

# == DEPLOY PROTOCOL WITH SUBGRAPH SERVICE ==
echo "No FORK_RPC_URL detected, deploying new version of the protocol"
cd /opt/contracts/packages/subgraph-service
npx hardhat deploy:protocol --network localNetwork --subgraph-service-config localNetwork

# Add legacy contracts to the deployed addresses (mounted file at addresses-local-network.json)
# The hardhat deployment doesn't include these, but the gateway needs them
# Use a temp variable to avoid breaking the Docker volume mount (mv creates a new inode)
TEMP_JSON=$(jq '.["1337"] += {
  "LegacyServiceRegistry": {"address": "0x0000000000000000000000000000000000000000"},
  "LegacyDisputeManager": {"address": "0x0000000000000000000000000000000000000000"}
}' addresses-local-network.json)
printf '%s\n' "$TEMP_JSON" > addresses-local-network.json

# == DEPLOY NETWORK SUBGRAPH ==
cp /opt/contracts/packages/horizon/addresses-local-network.json /opt/horizon.json
cp /opt/contracts/packages/subgraph-service/addresses-local-network.json /opt/subgraph-service.json
cd /opt/graph-network-subgraph

# Build and deploy the subgraph
npx ts-node config/localNetworkAddressScript.ts
npx mustache ./config/generatedAddresses.json ./config/addresses.template.ts > ./config/addresses.ts
npx mustache ./config/generatedAddresses.json subgraph.template.yaml > subgraph.yaml
echo -e "\n== Subgraph manifest ==\n"
cat subgraph.yaml
npx graph codegen --output-dir src/types/
npx graph create graph-network --node="http://graph-node:${GRAPH_NODE_ADMIN}"
npx graph deploy graph-network --node="http://graph-node:${GRAPH_NODE_ADMIN}" --ipfs="http://ipfs:${IPFS_RPC}" --version-label=v0.0.1

# Register DisputeManager in Controller (uses helper defined above)
ensure_dispute_manager_registered

# Keep the container running - for development purposes
if [ -n "${KEEP_CONTAINER_RUNNING:-}" ]; then
  tail -f /dev/null
fi
