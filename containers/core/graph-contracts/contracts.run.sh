#!/bin/bash
set -eu
. /opt/config/.env
. /opt/shared/lib.sh

# -- Ensure config files exist (empty JSON on first run) --
# horizon.json and subgraph-service.json are written here; issuance.json
# is read via symlink by the hardhat deploy task for cross-package lookups.
for f in horizon.json subgraph-service.json issuance.json; do
  [ -f "/opt/config/$f" ] || echo '{}' > "/opt/config/$f"
done

# -- Symlink Hardhat address books to config directory --
# Hardhat reads/writes addresses-local-network.json; symlinks let those
# writes land in /opt/config/ without individual Docker file mounts.
ln -sf /opt/config/horizon.json /opt/contracts/packages/horizon/addresses-local-network.json
ln -sf /opt/config/subgraph-service.json /opt/contracts/packages/subgraph-service/addresses-local-network.json
ln -sf /opt/config/issuance.json /opt/contracts/packages/issuance/addresses-local-network.json

echo "==== Phase 1: Graph protocol contracts ===="

# -- Helper: ensure DisputeManager registered in Controller --
ensure_dispute_manager_registered() {
  controller_address=$(jq -r '.["1337"].Controller.address // empty' /opt/config/horizon.json)
  dispute_manager_address=$(jq -r '.["1337"].DisputeManager.address // empty' /opt/config/subgraph-service.json)

  if [ -z "$controller_address" ] || [ -z "$dispute_manager_address" ]; then
    echo "Controller or DisputeManager address not found, skipping registration"
    return
  fi

  dispute_manager_id=$(cast keccak256 "DisputeManager")
  current_proxy=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
    "${controller_address}" "getContractProxy(bytes32)(address)" "${dispute_manager_id}" 2>/dev/null || echo "0x")

  current_proxy_lower=$(echo "$current_proxy" | tr '[:upper:]' '[:lower:]')
  dispute_manager_lower=$(echo "$dispute_manager_address" | tr '[:upper:]' '[:lower:]')

  if [ "$current_proxy_lower" = "$dispute_manager_lower" ]; then
    echo "DisputeManager already registered in Controller: ${dispute_manager_address}"
  else
    echo "Registering Horizon DisputeManager in Controller..."
    echo "  Controller: ${controller_address}"
    echo "  DisputeManager: ${dispute_manager_address}"
    echo "  Current proxy: ${current_proxy}"
    cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 --private-key="${ACCOUNT1_SECRET}" \
      "${controller_address}" "setContractProxy(bytes32,address)" "${dispute_manager_id}" "${dispute_manager_address}"
  fi
}

# -- Idempotency check --
skip=false
l2_graph_token=$(jq -r '.["1337"].L2GraphToken.address // empty' /opt/config/horizon.json 2>/dev/null || true)
if [ -n "$l2_graph_token" ]; then
  code_check=$(cast code --rpc-url="http://chain:${CHAIN_RPC_PORT}" "$l2_graph_token" 2>/dev/null || echo "0x")
  if [ "$code_check" != "0x" ]; then
    echo "Graph protocol contracts already deployed (L2GraphToken at $l2_graph_token)"
    ensure_dispute_manager_registered
    echo "SKIP: deploy"
    skip=true
  else
    echo "Contract addresses in horizon.json are stale (no code at $l2_graph_token), redeploying..."
  fi
fi

if [ "$skip" = "false" ]; then
  echo "Deploying new version of the protocol"
  # Clean stale Ignition state from previous localNetwork runs (dev overlay)
  rm -rf /opt/contracts/packages/subgraph-service/ignition/deployments/chain-1337
  cd /opt/contracts/packages/subgraph-service
  npx hardhat deploy:protocol --network localNetwork --subgraph-service-config localNetwork

  # Add legacy contract stubs (gateway needs these)
  TEMP_JSON=$(jq '.["1337"] += {
    "LegacyServiceRegistry": {"address": "0x0000000000000000000000000000000000000000"},
    "LegacyDisputeManager": {"address": "0x0000000000000000000000000000000000000000"}
  }' addresses-local-network.json)
  printf '%s\n' "$TEMP_JSON" > addresses-local-network.json

  ensure_dispute_manager_registered
fi

# -- Set issuance to 100 GRT/block for meaningful reward testing --
rewards_manager=$(jq -r '.["1337"].RewardsManager.address // empty' /opt/config/horizon.json)
if [ -n "$rewards_manager" ]; then
  target_issuance="100000000000000000000"  # 100 GRT in wei
  current_issuance=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
    "${rewards_manager}" "issuancePerBlock()(uint256)" 2>/dev/null | awk '{print $1}')
  if [ "$current_issuance" = "$target_issuance" ]; then
    echo "  issuancePerBlock already set to 100 GRT"
  else
    echo "  Setting issuancePerBlock to 100 GRT (was ${current_issuance})"
    cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 \
      --private-key="${ACCOUNT1_SECRET}" \
      "${rewards_manager}" "setIssuancePerBlock(uint256)" "${target_issuance}"
  fi
fi

echo "==== graph-contracts deploy complete ===="

# Optional: keep container running for debugging
if [ -n "${KEEP_CONTAINER_RUNNING:-}" ]; then
  tail -f /dev/null
fi
