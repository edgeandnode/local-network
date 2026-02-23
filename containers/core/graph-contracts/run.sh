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
# Phase 2: TAP contracts
# ============================================================
echo "==== Phase 2: TAP contracts ===="

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

echo "==== Phase 2 complete ===="

# ============================================================
# Phase 3: DataEdge contract
# ============================================================
echo "==== Phase 3: DataEdge contract ===="

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

echo "==== Phase 3 complete ===="

# ============================================================
# Phase 4: Rewards Eligibility Oracle (REO)
# ============================================================
if [ "${REO_ENABLED:-0}" != "1" ]; then
  echo "==== Phase 4: Rewards Eligibility Oracle (SKIPPED — REO_ENABLED not set) ===="
else
echo "==== Phase 4: Rewards Eligibility Oracle ===="

# Ensure NetworkOperator in issuance address book (required by configure step)
TEMP_JSON=$(jq --arg op "${ACCOUNT0_ADDRESS}" \
  '.["1337"].NetworkOperator = {"address": $op}' /opt/config/issuance.json)
printf '%s\n' "$TEMP_JSON" > /opt/config/issuance.json

# -- Idempotency check --
# The hardhat deploy configure step (04_configure.ts) targets REO_DEFAULTS
# (14d eligibility, 7d timeout) using the GOVERNOR account, which lacks
# OPERATOR_ROLE. run.sh below handles all configuration using ACCOUNT0
# (OPERATOR). So we only run hardhat deploy for initial deployment; on
# re-runs where the REO proxy already exists on-chain, skip straight to
# the idempotent configuration below.
phase4_deploy_skip=false
reo_address=$(jq -r '.["1337"].RewardsEligibilityOracle.address // empty' /opt/config/issuance.json 2>/dev/null || true)
if [ -n "$reo_address" ]; then
  code_check=$(cast code --rpc-url="http://chain:${CHAIN_RPC_PORT}" "$reo_address" 2>/dev/null || echo "0x")
  if [ "$code_check" != "0x" ]; then
    echo "REO already deployed at $reo_address"
    echo "SKIP: hardhat deploy (configuration handled below)"
    phase4_deploy_skip=true
  else
    echo "REO address stale (no code at $reo_address), redeploying..."
  fi
fi

if [ "$phase4_deploy_skip" = "false" ]; then
  cd /opt/contracts/packages/deployment

  # Clean any stale governance TX batches from partial runs
  rm -rf /opt/contracts/packages/deployment/txs/localNetwork

  # Full REO lifecycle via deployment package tags:
  #   sync → deploy → configure → transfer → integrate → verify
  # Deploy scripts are idempotent (skip if already deployed/configured).
  # The mnemonic provides both deployer (ACCOUNT0) and governor (ACCOUNT1),
  # so all steps including RM integration execute directly.
  #
  # Some steps (upgrade) exit with code 1 after saving governance TX batches.
  # On localNetwork, the governor key is available so we auto-execute and retry.
  export GOVERNOR_KEY="${ACCOUNT1_SECRET}"
  for attempt in 1 2 3; do
    echo "  Deploy attempt $attempt..."
    if npx hardhat deploy --tags rewards-eligibility --network localNetwork --skip-prompts; then
      break
    fi
    # Check for pending governance TXs and execute them
    if ls /opt/contracts/packages/deployment/txs/localNetwork/*.json 2>/dev/null | grep -qv executed; then
      echo "  Executing pending governance TXs..."
      npx hardhat deploy:execute-governance --network localNetwork || true
    else
      echo "  No governance TXs to execute, deployment failed for another reason"
      exit 1
    fi
  done

  # Read deployed REO address from issuance address book
  reo_address=$(jq -r '.["1337"].RewardsEligibilityOracle.address' /opt/config/issuance.json)
fi

echo "  REO deployed at: $reo_address"

# Grant ORACLE_ROLE to the REO node signing key (ACCOUNT0).
# OPERATOR_ROLE is the admin for ORACLE_ROLE, and ACCOUNT0 has OPERATOR_ROLE.
# Idempotent: only grants if not already granted.
oracle_role=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
  "${reo_address}" "ORACLE_ROLE()(bytes32)")
has_role=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
  "${reo_address}" "hasRole(bytes32,address)(bool)" "${oracle_role}" "${ACCOUNT0_ADDRESS}" 2>/dev/null || echo "false")
if [ "$has_role" = "true" ]; then
  echo "  ORACLE_ROLE already granted to ${ACCOUNT0_ADDRESS}"
else
  echo "  Granting ORACLE_ROLE to ${ACCOUNT0_ADDRESS} (via OPERATOR_ROLE)"
  cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 \
    --private-key="${ACCOUNT0_SECRET}" \
    "${reo_address}" "grantRole(bytes32,address)" "${oracle_role}" "${ACCOUNT0_ADDRESS}"
fi

# Enable eligibility validation (deny-by-default).
# The contract defaults to validation disabled (everyone eligible). For local
# testing we want the realistic deny-by-default behaviour. Idempotent.
# Requires OPERATOR_ROLE (ACCOUNT0).
validation_enabled=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
  "${reo_address}" "getEligibilityValidation()(bool)" 2>/dev/null || echo "false")
if [ "$validation_enabled" = "true" ]; then
  echo "  Eligibility validation already enabled"
else
  echo "  Enabling eligibility validation (deny-by-default)"
  cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 \
    --private-key="${ACCOUNT0_SECRET}" \
    "${reo_address}" "setEligibilityValidation(bool)" true
fi

# Set eligibility period (how long an indexer stays eligible after renewal).
# Contract default is 14 days; local network uses a short value for fast iteration.
# Requires OPERATOR_ROLE (ACCOUNT0).
current_period=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
  "${reo_address}" "getEligibilityPeriod()(uint256)" 2>/dev/null | awk '{print $1}')
if [ "$current_period" = "${REO_ELIGIBILITY_PERIOD}" ]; then
  echo "  Eligibility period already set to ${REO_ELIGIBILITY_PERIOD}s"
else
  echo "  Setting eligibility period to ${REO_ELIGIBILITY_PERIOD}s (was ${current_period}s)"
  cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 \
    --private-key="${ACCOUNT0_SECRET}" \
    "${reo_address}" "setEligibilityPeriod(uint256)" "${REO_ELIGIBILITY_PERIOD}"
fi

# Set oracle update timeout (fail-safe: all indexers eligible if no oracle update for this long).
# Contract default is 7 days; local network uses a longer value to avoid accidental fail-safe.
# Requires OPERATOR_ROLE (ACCOUNT0).
current_timeout=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
  "${reo_address}" "getOracleUpdateTimeout()(uint256)" 2>/dev/null | awk '{print $1}')
if [ "$current_timeout" = "${REO_ORACLE_UPDATE_TIMEOUT}" ]; then
  echo "  Oracle update timeout already set to ${REO_ORACLE_UPDATE_TIMEOUT}s"
else
  echo "  Setting oracle update timeout to ${REO_ORACLE_UPDATE_TIMEOUT}s (was ${current_timeout}s)"
  cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 \
    --private-key="${ACCOUNT0_SECRET}" \
    "${reo_address}" "setOracleUpdateTimeout(uint256)" "${REO_ORACLE_UPDATE_TIMEOUT}"
fi

# Clean deployment metadata from address books.
# The deployment package writes fields like implementationDeployment and
# proxyDeployment that the indexer-agent doesn't recognise, causing it to
# crash with "Address book entry contains invalid fields".
for ab in horizon.json subgraph-service.json; do
  if [ -f "/opt/config/$ab" ]; then
    TEMP_JSON=$(jq 'walk(if type == "object" then del(.implementationDeployment, .proxyDeployment) else . end)' "/opt/config/$ab")
    printf '%s\n' "$TEMP_JSON" > "/opt/config/$ab"
  fi
done

echo "==== Phase 4 complete ===="
fi  # REO_ENABLED
echo "==== All contract deployments complete ===="

# Optional: keep container running for debugging
if [ -n "${KEEP_CONTAINER_RUNNING:-}" ]; then
  tail -f /dev/null
fi
