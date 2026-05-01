#!/bin/bash
set -eu
# shellcheck source=/dev/null
. /opt/config/.env
# shellcheck source=/dev/null
. /opt/shared/lib.sh

# -- Ensure config files exist (empty JSON on first run) --
# horizon.json, subgraph-service.json, and block-oracle.json are written
# here; issuance.json is read via symlink by the hardhat deploy task for
# cross-package lookups.
for f in horizon.json subgraph-service.json issuance.json block-oracle.json; do
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

echo "==== Phase 1 complete ===="

# ============================================================
# Phase 2: DataEdge contract (for block-oracle)
# ============================================================
# Uses packages/data-edge from the same contracts workspace. Independent
# of Phase 1 — no shared state on-chain — but bundled here because it
# shares the same pnpm / hardhat toolchain and built workspace artifacts.
echo "==== Phase 2: DataEdge contract ===="

# -- Idempotency check --
phase2_skip=false
data_edge=$(jq -r '."1337".DataEdge // empty' /opt/config/block-oracle.json 2>/dev/null || true)
if [ -n "$data_edge" ]; then
  code_check=$(cast code --rpc-url="http://chain:${CHAIN_RPC_PORT}" "$data_edge" 2>/dev/null || echo "0x")
  if [ "$code_check" != "0x" ]; then
    echo "DataEdge contract already deployed at $data_edge"
    echo "SKIP: Phase 2"
    phase2_skip=true
  else
    echo "DataEdge address stale (no code at $data_edge), redeploying..."
  fi
fi

if [ "$phase2_skip" = "false" ]; then
  cd /opt/contracts/packages/data-edge
  # hardhat.config.ts hardcodes `localhost:8545` for the ganache network
  # and the standard test mnemonic; patch both for the local-network stack.
  sed -i "s/localhost/chain/g" hardhat.config.ts
  sed -i "s/myth like bonus scare over problem client lizard pioneer submit female collect/${MNEMONIC}/g" hardhat.config.ts
  export MNEMONIC="${MNEMONIC}"

  npx hardhat data-edge:deploy --contract EventfulDataEdge --deploy-name EBO --network ganache | tee deploy.txt
  data_edge="$(grep 'contract: ' deploy.txt | awk '{print $3}')"
  echo "=== DataEdge deployed at: $data_edge ==="

  cat <<ADDR_EOF > /opt/config/block-oracle.json
{
  "1337": {
    "DataEdge": "$data_edge"
  }
}
ADDR_EOF

  # Register network in DataEdge (pre-encoded setMessage calldata for eip155:1337)
  output=$(cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 --mnemonic="${MNEMONIC}" \
    "${data_edge}" \
    '0xa1dce3320000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000f030103176569703135353a313333370000000000000000000000000000000000' 2>&1)
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "Error during cast send: $output" | tee -a error.log
  else
    echo "$output"
  fi
fi

echo "==== Phase 2 complete ===="
echo "==== graph-contracts deploy complete ===="

# Optional: keep container running for debugging
if [ -n "${KEEP_CONTAINER_RUNNING:-}" ]; then
  tail -f /dev/null
fi
