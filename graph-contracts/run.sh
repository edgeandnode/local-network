#!/bin/bash
set -eu
. /opt/config/.env
. /opt/shared/lib.sh

# -- Ensure config files exist (empty JSON on first run) --
for f in horizon.json subgraph-service.json issuance.json tap-contracts.json block-oracle.json; do
  [ -f "/opt/config/$f" ] || echo '{}' > "/opt/config/$f"
done

# -- Symlink Hardhat address books to config directory --
# Hardhat reads/writes addresses-local-network.json; symlinks let those
# writes land in /opt/config/ without individual Docker file mounts.
ln -sf /opt/config/horizon.json /opt/contracts/packages/horizon/addresses-local-network.json
ln -sf /opt/config/subgraph-service.json /opt/contracts/packages/subgraph-service/addresses-local-network.json
ln -sf /opt/config/issuance.json /opt/contracts/packages/issuance/addresses-local-network.json

# ============================================================
# Phase 1: Graph protocol contracts
# ============================================================
echo "==== Phase 1/3: Graph protocol contracts ===="

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
phase1_skip=false
l2_graph_token=$(jq -r '.["1337"].L2GraphToken.address // empty' /opt/config/horizon.json 2>/dev/null || true)
if [ -n "$l2_graph_token" ]; then
  code_check=$(cast code --rpc-url="http://chain:${CHAIN_RPC_PORT}" "$l2_graph_token" 2>/dev/null || echo "0x")
  if [ "$code_check" != "0x" ]; then
    echo "Graph protocol contracts already deployed (L2GraphToken at $l2_graph_token)"
    ensure_dispute_manager_registered
    echo "SKIP: Phase 1"
    phase1_skip=true
  else
    echo "Contract addresses in horizon.json are stale (no code at $l2_graph_token), redeploying..."
  fi
fi

if [ "$phase1_skip" = "false" ]; then
  echo "Deploying new version of the protocol"
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

echo "==== Phase 1/3 complete ===="

# ============================================================
# Phase 2: TAP contracts
# ============================================================
echo "==== Phase 2/3: TAP contracts ===="

# -- Idempotency check --
phase2_skip=false
escrow_address=$(jq -r '."1337".Escrow // empty' /opt/config/tap-contracts.json 2>/dev/null || true)
if [ -n "$escrow_address" ]; then
  code_check=$(cast code --rpc-url="http://chain:${CHAIN_RPC_PORT}" "$escrow_address" 2>/dev/null || echo "0x")
  if [ "$code_check" != "0x" ]; then
    echo "TAP contracts already deployed (Escrow at $escrow_address)"
    echo "SKIP: Phase 2"
    phase2_skip=true
  else
    echo "TAP contract addresses are stale (no code at Escrow $escrow_address), redeploying..."
  fi
fi

if [ "$phase2_skip" = "false" ]; then
  cd /opt/timeline-aggregation-protocol-contracts

  staking=$(contract_addr HorizonStaking.address horizon)
  graph_token=$(contract_addr L2GraphToken.address horizon)

  # Note: forge may output alloy log lines to stdout after the JSON; sed extracts only the JSON object
  forge create --broadcast --json --rpc-url="http://chain:${CHAIN_RPC_PORT}" --mnemonic="${MNEMONIC}" \
    src/AllocationIDTracker.sol:AllocationIDTracker \
    | tee allocation_tracker.json
  allocation_tracker="$(sed -n '/^{/,/^}/p' allocation_tracker.json | jq -r '.deployedTo')"

  forge create --broadcast --json --rpc-url="http://chain:${CHAIN_RPC_PORT}" --mnemonic="${MNEMONIC}" \
    src/TAPVerifier.sol:TAPVerifier --constructor-args 'TAP' '1' \
    | tee verifier.json
  verifier="$(sed -n '/^{/,/^}/p' verifier.json | jq -r '.deployedTo')"

  forge create --broadcast --json --rpc-url="http://chain:${CHAIN_RPC_PORT}" --mnemonic="${MNEMONIC}" \
    src/Escrow.sol:Escrow --constructor-args "${graph_token}" "${staking}" "${verifier}" "${allocation_tracker}" 10 15 \
    | tee escrow.json
  escrow="$(sed -n '/^{/,/^}/p' escrow.json | jq -r '.deployedTo')"

  cat <<EOF > /opt/config/tap-contracts.json
{
  "1337": {
    "AllocationIDTracker": "$allocation_tracker",
    "TAPVerifier": "$verifier",
    "Escrow": "$escrow"
  }
}
EOF
fi

echo "==== Phase 2/3 complete ===="

# ============================================================
# Phase 3: DataEdge contract
# ============================================================
echo "==== Phase 3/3: DataEdge contract ===="

# -- Idempotency check --
phase3_skip=false
data_edge=$(jq -r '."1337".DataEdge // empty' /opt/config/block-oracle.json 2>/dev/null || true)
if [ -n "$data_edge" ]; then
  code_check=$(cast code --rpc-url="http://chain:${CHAIN_RPC_PORT}" "$data_edge" 2>/dev/null || echo "0x")
  if [ "$code_check" != "0x" ]; then
    echo "DataEdge contract already deployed at $data_edge"
    echo "SKIP: Phase 3"
    phase3_skip=true
  else
    echo "DataEdge address stale (no code at $data_edge), redeploying..."
  fi
fi

if [ "$phase3_skip" = "false" ]; then
  cd /opt/contracts-data-edge/packages/data-edge
  export MNEMONIC="${MNEMONIC}"
  sed -i "s/myth like bonus scare over problem client lizard pioneer submit female collect/${MNEMONIC}/g" hardhat.config.ts
  npx hardhat data-edge:deploy --contract EventfulDataEdge --deploy-name EBO --network ganache | tee deploy.txt
  data_edge="$(grep 'contract: ' deploy.txt | awk '{print $3}')"

  echo "=== Data edge deployed at: $data_edge ==="

  cat <<ADDR_EOF > /opt/config/block-oracle.json
{
  "1337": {
    "DataEdge": "$data_edge"
  }
}
ADDR_EOF

  # Register network in DataEdge
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

echo "==== Phase 3/3 complete ===="
echo "==== All contract deployments complete ===="

# Optional: keep container running for debugging
if [ -n "${KEEP_CONTAINER_RUNNING:-}" ]; then
  tail -f /dev/null
fi
