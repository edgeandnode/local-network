#!/bin/bash
set -eu
# shellcheck source=/dev/null
. /opt/config/.env
# shellcheck source=/dev/null
. /opt/shared/lib.sh

# -- Ensure config files exist (empty JSON on first run) --
for f in horizon.json subgraph-service.json issuance.json block-oracle.json; do
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

  # Clear stale Ignition deployment state (may be baked into the image)
  rm -rf ./ignition/deployments/chain-1337
  rm -rf /opt/contracts/packages/horizon/ignition/deployments/chain-1337

  npx hardhat deploy:protocol --network localNetwork --subgraph-service-config localNetwork

  # Add legacy contract stubs (network subgraph still references them).
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

# -- Ensure SubgraphService is registered as rewards issuer on RewardsManager --
subgraph_service=$(jq -r '.["1337"].SubgraphService.address // empty' /opt/config/subgraph-service.json)
if [ -n "$rewards_manager" ] && [ -n "$subgraph_service" ]; then
  current_service=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
    "${rewards_manager}" "subgraphService()(address)" 2>/dev/null | tr '[:upper:]' '[:lower:]')
  expected_lower=$(echo "$subgraph_service" | tr '[:upper:]' '[:lower:]')
  if [ "$current_service" = "$expected_lower" ]; then
    echo "  SubgraphService already set on RewardsManager: ${subgraph_service}"
  else
    echo "  Setting SubgraphService on RewardsManager to ${subgraph_service} (was ${current_service})"
    cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 \
      --private-key="${ACCOUNT1_SECRET}" \
      "${rewards_manager}" "setSubgraphService(address)" "${subgraph_service}"
  fi
fi

# Stub tap-contracts.json for chain 1337: the indexer-agent's tap-contracts-
# bindings hardcodes per-chain TAP addresses and has none for 1337, so map the
# legacy names to Horizon equivalents (AllocationIDTracker unused -> zero stub).
graph_tally_collector=$(jq -r '."1337".GraphTallyCollector.address' /opt/config/horizon.json)
payments_escrow=$(jq -r '."1337".PaymentsEscrow.address' /opt/config/horizon.json)
cat > /opt/config/tap-contracts.json <<EOF
{
  "1337": {
    "TAPVerifier": "${graph_tally_collector}",
    "AllocationIDTracker": "0x0000000000000000000000000000000000000000",
    "Escrow": "${payments_escrow}"
  }
}
EOF

echo "==== Phase 1 complete ===="

# ============================================================
# Phase 2: DataEdge contract
# ============================================================
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
  # hardhat.config.ts hardcodes `localhost:8545` for the ganache network and
  # the standard test mnemonic; patch both for the local-network stack.
  # (The previous pinned-clone setup did the localhost→chain sed at build time.)
  sed -i "s/localhost/chain/g" hardhat.config.ts
  sed -i "s/myth like bonus scare over problem client lizard pioneer submit female collect/${MNEMONIC}/g" hardhat.config.ts
  export MNEMONIC="${MNEMONIC}"
  # Tenderly verification may fail (external API, irrelevant locally) but
  # the contract deploys fine. Allow non-zero exit from the hardhat command.
  npx hardhat data-edge:deploy --contract EventfulDataEdge --deploy-name EBO --network ganache | tee deploy.txt || true
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

echo "==== Phase 2 complete ===="

# ============================================================
# Phase 3: GIP-0088 issuance contracts (RecurringAgreementManager, etc.)
# ============================================================
echo "==== Phase 3: GIP-0088 issuance contracts ===="

# DIPs needs RecurringAgreementManager on-chain: the indexing-payments subgraph
# indexes it, and dipper's offers are gated by AGREEMENT_MANAGER_ROLE on it. We
# deploy the issuance set but do NOT wire RewardsManager into it (see below).

cd /opt/contracts/packages/deployment

# At contracts 14823afc, localNetwork resolves the deployer from a single key env
# var (not the test mnemonic) and the governor cannot sign directly, so each
# governance batch is drained with deploy:execute-governance.
export LOCAL_NETWORK_DEPLOYER_KEY="${ACCOUNT0_SECRET}"
export GOVERNOR_KEY="${ACCOUNT1_SECRET}"
export LOCAL_NETWORK_GOVERNOR_KEY="${ACCOUNT1_SECRET}"
export LOCAL_NETWORK_RPC="http://chain:${CHAIN_RPC_PORT}"

# NetworkOperator is a precondition of the configure step's role grants.
TEMP_JSON=$(jq --arg op "${ACCOUNT0_ADDRESS}" \
  '.["1337"].NetworkOperator = {"address": $op}' /opt/config/issuance.json)
printf '%s\n' "$TEMP_JSON" > /opt/config/issuance.json

# Run one deploy tag, draining any governance batch it saves and retrying.
run_issuance_stage() {
  rm -rf /opt/contracts/packages/deployment/txs/localNetwork
  for attempt in 1 2 3 4 5; do
    echo "  Stage '$1' attempt $attempt..."
    if npx hardhat deploy --tags "$1" --network localNetwork --skip-prompts; then
      return 0
    fi
    if find /opt/contracts/packages/deployment/txs/localNetwork/ -name '*.json' ! -name '*executed*' -print -quit 2>/dev/null | grep -q .; then
      echo "  Executing pending governance TXs for $1..."
      npx hardhat deploy:execute-governance --network localNetwork || true
    else
      echo "  Stage '$1' failed with no governance batch to drain"
      return 1
    fi
  done
  return 1
}

# Deploy + configure the issuance contracts and the mock oracle, then connect the
# protocol-funded flow so RecurringAgreementManager (RAM) receives issuance. Still
# skip eligibility-integrate: it gates indexing rewards, off the DIPs funding path.
run_issuance_stage "GIP-0088:upgrade,deploy"
run_issuance_stage "GIP-0088:upgrade,configure"
run_issuance_stage "RewardsEligibilityOracleMock,deploy,configure"

# Route issuance to RAM, else its beforeCollection() escrow top-up has nothing to
# deposit and DIPs collect() reverts on an empty escrow. issuance-allocate needs the
# config table to sum to RM's on-chain 100 GRT/block, so fill it: 94 (RM) + 6 (RAM).
ISSUANCE_CONFIG=/opt/contracts/packages/deployment/config/localNetwork.json5
sed -i \
  -e "s|// issuancePerBlock: '<RM issuancePerBlock>',|issuancePerBlock: '100',|" \
  -e "s|// RewardsManager: { selfGrtPerBlock: '<issuancePerBlock - 6>' },|RewardsManager: { selfGrtPerBlock: '94' },|" \
  "$ISSUANCE_CONFIG"
if grep -q "issuancePerBlock: '100'" "$ISSUANCE_CONFIG"; then
  echo "  Issuance allocation table set: 100 GRT/block = 94 (RM self) + 6 (RAM)"
else
  echo "  WARNING: issuance config patch did not apply; issuance-allocate will validate" >&2
fi

run_issuance_stage "GIP-0088:issuance-connect"
run_issuance_stage "GIP-0088:issuance-allocate"

# Grant AGREEMENT_MANAGER_ROLE on RAM to the DIPs payer (ACCOUNT0) so dipper's
# offers pass the indexer-service trust gate. ACCOUNT0 holds GOVERNOR_ROLE, which
# admins OPERATOR_ROLE, which admins this role — so it self-grants both in turn.
ram_address=$(jq -r '.["1337"].RecurringAgreementManager.address' /opt/config/issuance.json)
operator_role=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" "${ram_address}" "OPERATOR_ROLE()(bytes32)")
agreement_manager_role=$(cast keccak "AGREEMENT_MANAGER_ROLE")
has_am_role=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
  "${ram_address}" "hasRole(bytes32,address)(bool)" "${agreement_manager_role}" "${ACCOUNT0_ADDRESS}" 2>/dev/null || echo "false")
if [ "$has_am_role" = "true" ]; then
  echo "  AGREEMENT_MANAGER_ROLE already granted to ${ACCOUNT0_ADDRESS}"
else
  echo "  Granting AGREEMENT_MANAGER_ROLE to ${ACCOUNT0_ADDRESS}"
  cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 \
    --private-key="${ACCOUNT0_SECRET}" \
    "${ram_address}" "grantRole(bytes32,address)" "${operator_role}" "${ACCOUNT0_ADDRESS}"
  cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 \
    --private-key="${ACCOUNT0_SECRET}" \
    "${ram_address}" "grantRole(bytes32,address)" "${agreement_manager_role}" "${ACCOUNT0_ADDRESS}"
fi

# Strip deployment metadata (implementationDeployment/proxyDeployment) the
# indexer-agent can't parse, now also covering issuance.json.
for ab in horizon.json subgraph-service.json issuance.json; do
  if [ -f "/opt/config/$ab" ]; then
    TEMP_JSON=$(jq 'walk(if type == "object" then del(.implementationDeployment, .proxyDeployment) else . end)' "/opt/config/$ab")
    printf '%s\n' "$TEMP_JSON" > "/opt/config/$ab"
  fi
done

echo "==== Phase 3 complete ===="
echo "==== All contract deployments complete ===="

# Optional: keep container running for debugging
if [ -n "${KEEP_CONTAINER_RUNNING:-}" ]; then
  tail -f /dev/null
fi
