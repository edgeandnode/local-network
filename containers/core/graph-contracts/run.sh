#!/bin/bash
set -eu
. /opt/config/.env
. /opt/shared/lib.sh

# -- Ensure config files exist (empty JSON on first run) --
for f in horizon.json subgraph-service.json issuance.json block-oracle.json; do
  [ -f "/opt/config/$f" ] || echo '{}' > "/opt/config/$f"
done

# -- Symlink Hardhat address books to config directory --
# Hardhat reads/writes addresses-local-network.json; symlinks let those
# writes land in /opt/config/ without individual Docker file mounts.
# Guarded per package: the baseline contract image (mainnet-deployed
# surface) ships no issuance package.
for pkg_book in horizon:horizon.json subgraph-service:subgraph-service.json issuance:issuance.json; do
  pkg="${pkg_book%%:*}"; book="${pkg_book#*:}"
  if [ -d "/opt/contracts/packages/${pkg}" ]; then
    ln -sf "/opt/config/${book}" "/opt/contracts/packages/${pkg}/addresses-local-network.json"
  else
    echo "Package ${pkg} not present in this contracts image — skipping address-book symlink"
  fi
done

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
    cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 --private-key="${GOVERNOR_SECRET}" \
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
      --private-key="${GOVERNOR_SECRET}" \
      "${rewards_manager}" "setIssuancePerBlock(uint256)" "${target_issuance}"
  fi
fi

# -- Ensure the subgraph availability oracle matches the role-named account --
# The mainnet-deployed protocol config hardcodes a stale SAO address (ganache
# mnemonic index 4); local-network's accounts use the hardhat test mnemonic.
# Idempotent governance fixup, same pattern as issuancePerBlock above.
if [ -n "$rewards_manager" ] && [ -n "${SUBGRAPH_AVAILABILITY_ORACLE_ADDRESS:-}" ]; then
  current_sao=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
    "${rewards_manager}" "subgraphAvailabilityOracle()(address)" 2>/dev/null | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
  wanted_sao=$(echo "${SUBGRAPH_AVAILABILITY_ORACLE_ADDRESS}" | tr '[:upper:]' '[:lower:]')
  if [ "$current_sao" = "$wanted_sao" ]; then
    echo "  subgraphAvailabilityOracle already set to ${SUBGRAPH_AVAILABILITY_ORACLE_ADDRESS}"
  else
    echo "  Setting subgraphAvailabilityOracle to ${SUBGRAPH_AVAILABILITY_ORACLE_ADDRESS} (was ${current_sao})"
    cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 \
      --private-key="${GOVERNOR_SECRET}" \
      "${rewards_manager}" "setSubgraphAvailabilityOracle(address)" "${SUBGRAPH_AVAILABILITY_ORACLE_ADDRESS}"
  fi
fi

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

echo "==== Phase 2 complete ===="

# ============================================================
# Phase 3: GIP-0088 — REO + IssuanceAllocator + RecurringAgreementManager
# ============================================================
if [ "${GIP0088_ENABLED:-0}" != "1" ]; then
  echo "==== Phase 3: GIP-0088 (SKIPPED — GIP0088_ENABLED not set) ===="
else
echo "==== Phase 3: GIP-0088 ===="

# Address-book entries that the GIP-0088 configure step reads:
#   NetworkOperator → granted OPERATOR_ROLE on REO. Use OPERATOR_ADDRESS so
#   the operator's nonce queue is independent of the deployer's.
TEMP_JSON=$(jq --arg op "${OPERATOR_ADDRESS}" \
  '.["1337"].NetworkOperator = {"address": $op}' /opt/config/issuance.json)
printf '%s\n' "$TEMP_JSON" > /opt/config/issuance.json

# Controller.pauseGuardian → granted PAUSE_ROLE on REO by the configure step
# (read from Controller.pauseGuardian() at configure time, not from address
# book). Set it to PAUSE_ADMIN_ADDRESS before Phase 4 runs so PAUSE_ROLE
# lands on a dedicated account.
controller_address=$(jq -r '.["1337"].Controller.address // empty' /opt/config/horizon.json 2>/dev/null || true)
if [ -n "${controller_address}" ]; then
  current_guardian=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
    "${controller_address}" "pauseGuardian()(address)" 2>/dev/null || echo "0x")
  current_lc=$(echo "$current_guardian" | tr '[:upper:]' '[:lower:]')
  target_lc=$(echo "$PAUSE_ADMIN_ADDRESS" | tr '[:upper:]' '[:lower:]')
  if [ "$current_lc" = "$target_lc" ]; then
    echo "Controller pauseGuardian already ${PAUSE_ADMIN_ADDRESS}"
  else
    echo "Setting Controller pauseGuardian to ${PAUSE_ADMIN_ADDRESS} (was ${current_guardian})"
    cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 \
      --private-key="${GOVERNOR_SECRET}" \
      "${controller_address}" "setPauseGuardian(address)" "${PAUSE_ADMIN_ADDRESS}"
  fi
fi

# -- Idempotency check --
# Skip the whole deployment when REO + IA + RAM are all on-chain and IA is
# wired as a minter on GraphToken (proves the activation goals ran).
phase3_skip=false
ram_address=$(jq -r '.["1337"].RecurringAgreementManager.address // empty' /opt/config/issuance.json 2>/dev/null || true)
ia_address=$(jq -r '.["1337"].IssuanceAllocator.address // empty' /opt/config/issuance.json 2>/dev/null || true)
reo_address=$(jq -r '.["1337"].RewardsEligibilityOracleA.address // empty' /opt/config/issuance.json 2>/dev/null || true)
if [ -n "$ram_address" ] && [ -n "$ia_address" ] && [ -n "$reo_address" ]; then
  ram_code=$(cast code --rpc-url="http://chain:${CHAIN_RPC_PORT}" "$ram_address" 2>/dev/null || echo "0x")
  ia_code=$(cast code --rpc-url="http://chain:${CHAIN_RPC_PORT}" "$ia_address" 2>/dev/null || echo "0x")
  reo_code=$(cast code --rpc-url="http://chain:${CHAIN_RPC_PORT}" "$reo_address" 2>/dev/null || echo "0x")
  if [ "$ram_code" != "0x" ] && [ "$ia_code" != "0x" ] && [ "$reo_code" != "0x" ]; then
    graph_token=$(contract_addr L2GraphToken.address horizon)
    ia_is_minter=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
      "${graph_token}" "isMinter(address)(bool)" "${ia_address}" 2>/dev/null || echo "false")
    if [ "$ia_is_minter" = "true" ]; then
      echo "GIP-0088 contracts already deployed and activated"
      echo "  REO: $reo_address"
      echo "  IA:  $ia_address"
      echo "  RAM: $ram_address"
      phase3_skip=true
    fi
  fi
fi

if [ "$phase3_skip" = "false" ]; then
  cd /opt/contracts/packages/deployment

  # Clean stale deployment state from previous localNetwork runs
  rm -rf /opt/contracts/packages/deployment/txs/localNetwork
  rm -rf /opt/contracts/packages/deployment/deployments/localNetwork

  # On localNetwork the governor key is available, so governance TXs
  # auto-execute via deploy:execute-governance.
  export GOVERNOR_KEY="${GOVERNOR_SECRET}"

  # -- GIP-0088 Upgrade Phase --
  # Deploy → configure → transfer → upgrade. Each step is idempotent and may
  # produce governance TXs that need executing before the next attempt.
  for step in \
    "GIP-0088:upgrade,deploy" \
    "GIP-0088:upgrade,configure" \
    "GIP-0088:upgrade,transfer" \
    "GIP-0088:upgrade,upgrade"; do
    echo "  --- Running: --tags ${step} ---"
    for attempt in 1 2 3; do
      if pnpm exec hardhat deploy --tags "${step}" --network localNetwork --skip-prompts; then
        break
      fi
      if ls /opt/contracts/packages/deployment/txs/localNetwork/*.json 2>/dev/null | grep -qv executed; then
        echo "  Executing pending governance TXs..."
        pnpm exec hardhat deploy:execute-governance --network localNetwork || true
      else
        echo "  Deploy step failed (no governance TXs pending)"
        exit 1
      fi
    done
    if ls /opt/contracts/packages/deployment/txs/localNetwork/*.json 2>/dev/null | grep -qv executed; then
      echo "  Executing governance TXs..."
      pnpm exec hardhat deploy:execute-governance --network localNetwork || true
    fi
  done

  # -- GIP-0088 Activation Goals --
  # Each goal generates governance TXs independently; execute after each.
  for goal in \
    "GIP-0088:eligibility-integrate" \
    "GIP-0088:issuance-connect" \
    "GIP-0088:issuance-allocate"; do
    echo "  --- Running: --tags ${goal} ---"
    for attempt in 1 2 3; do
      if pnpm exec hardhat deploy --tags "${goal}" --network localNetwork --skip-prompts; then
        break
      fi
      if ls /opt/contracts/packages/deployment/txs/localNetwork/*.json 2>/dev/null | grep -qv executed; then
        echo "  Executing pending governance TXs..."
        pnpm exec hardhat deploy:execute-governance --network localNetwork || true
      else
        echo "  Activation goal failed (no governance TXs pending)"
        exit 1
      fi
    done
    if ls /opt/contracts/packages/deployment/txs/localNetwork/*.json 2>/dev/null | grep -qv executed; then
      echo "  Executing governance TXs..."
      pnpm exec hardhat deploy:execute-governance --network localNetwork || true
    fi
  done

  # Read deployed addresses
  reo_address=$(jq -r '.["1337"].RewardsEligibilityOracleA.address' /opt/config/issuance.json)
  ia_address=$(jq -r '.["1337"].IssuanceAllocator.address' /opt/config/issuance.json)
  ram_address=$(jq -r '.["1337"].RecurringAgreementManager.address' /opt/config/issuance.json)
fi

echo "  REO deployed at: ${reo_address:-<not deployed>}"
echo "  IA deployed at:  ${ia_address:-<not deployed>}"
echo "  RAM deployed at: ${ram_address:-<not deployed>}"

# -- REO local-network ORACLE_ROLE grant (deployment-package gap) --
# The GIP-0088 configure step grants GOVERNOR_ROLE / OPERATOR_ROLE (via
# NetworkOperator address-book entry, set above) and PAUSE_ROLE (via
# Controller.pauseGuardian, set above). It does NOT grant ORACLE_ROLE —
# `createREORoleConditions` in @graphprotocol/deployment omits it. Until that
# upstream gap is fixed, grant it here, signed by OPERATOR_SECRET (which now
# holds OPERATOR_ROLE, the admin of ORACLE_ROLE per RewardsEligibilityOracle.sol:125).
# Also keep DEPLOYER's existing ORACLE_ROLE grant for transitional compatibility
# with services (eligibility-oracle-node, dipper) that may still sign with it.
if [ -n "${reo_address:-}" ]; then
  oracle_role=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
    "${reo_address}" "ORACLE_ROLE()(bytes32)")

  for grantee in "${ORACLE_ADDRESS}" "${DEPLOYER_ADDRESS}"; do
    has=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
      "${reo_address}" "hasRole(bytes32,address)(bool)" "${oracle_role}" "${grantee}" 2>/dev/null || echo "false")
    if [ "$has" = "true" ]; then
      echo "  ORACLE_ROLE already granted to ${grantee}"
    else
      echo "  Granting ORACLE_ROLE to ${grantee} (signed by OPERATOR)"
      cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 \
        --private-key="${OPERATOR_SECRET}" \
        "${reo_address}" "grantRole(bytes32,address)" "${oracle_role}" "${grantee}"
    fi
  done

  # Enable eligibility validation (deny-by-default).
  validation_enabled=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
    "${reo_address}" "getEligibilityValidation()(bool)" 2>/dev/null || echo "false")
  if [ "$validation_enabled" = "true" ]; then
    echo "  Eligibility validation already enabled"
  else
    echo "  Enabling eligibility validation (deny-by-default)"
    cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 \
      --private-key="${OPERATOR_SECRET}" \
      "${reo_address}" "setEligibilityValidation(bool)" true
  fi

  # Set eligibility period (short value for fast iteration).
  current_period=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
    "${reo_address}" "getEligibilityPeriod()(uint256)" 2>/dev/null | awk '{print $1}')
  if [ "$current_period" = "${REO_ELIGIBILITY_PERIOD}" ]; then
    echo "  Eligibility period already set to ${REO_ELIGIBILITY_PERIOD}s"
  else
    echo "  Setting eligibility period to ${REO_ELIGIBILITY_PERIOD}s (was ${current_period}s)"
    cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 \
      --private-key="${OPERATOR_SECRET}" \
      "${reo_address}" "setEligibilityPeriod(uint256)" "${REO_ELIGIBILITY_PERIOD}"
  fi

  # Set oracle update timeout (long value to avoid accidental fail-safe).
  current_timeout=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
    "${reo_address}" "getOracleUpdateTimeout()(uint256)" 2>/dev/null | awk '{print $1}')
  if [ "$current_timeout" = "${REO_ORACLE_UPDATE_TIMEOUT}" ]; then
    echo "  Oracle update timeout already set to ${REO_ORACLE_UPDATE_TIMEOUT}s"
  else
    echo "  Setting oracle update timeout to ${REO_ORACLE_UPDATE_TIMEOUT}s (was ${current_timeout}s)"
    cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 \
      --private-key="${OPERATOR_SECRET}" \
      "${reo_address}" "setOracleUpdateTimeout(uint256)" "${REO_ORACLE_UPDATE_TIMEOUT}"
  fi
fi

# Grant AGREEMENT_MANAGER_ROLE to the dipper signer (DEPLOYER) — the indexer's DIPs
# trust gate only accepts proposals from a role holder. Admin chain is GOVERNOR ->
# OPERATOR -> AGREEMENT_MANAGER, none held post-deploy, so grant both. Idempotent.
if [ -n "${ram_address:-}" ]; then
  operator_role=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" "${ram_address}" "OPERATOR_ROLE()(bytes32)")
  am_role=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" "${ram_address}" "AGREEMENT_MANAGER_ROLE()(bytes32)")

  op_has=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" "${ram_address}" \
    "hasRole(bytes32,address)(bool)" "${operator_role}" "${OPERATOR_ADDRESS}" 2>/dev/null || echo false)
  if [ "$op_has" != "true" ]; then
    echo "  Granting OPERATOR_ROLE on RAM to ${OPERATOR_ADDRESS} (signed by GOVERNOR)"
    cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 --private-key="${GOVERNOR_SECRET}" \
      "${ram_address}" "grantRole(bytes32,address)" "${operator_role}" "${OPERATOR_ADDRESS}"
  fi

  am_has=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" "${ram_address}" \
    "hasRole(bytes32,address)(bool)" "${am_role}" "${DEPLOYER_ADDRESS}" 2>/dev/null || echo false)
  if [ "$am_has" = "true" ]; then
    echo "  AGREEMENT_MANAGER_ROLE already granted to ${DEPLOYER_ADDRESS}"
  else
    echo "  Granting AGREEMENT_MANAGER_ROLE to ${DEPLOYER_ADDRESS} (dipper signer, signed by OPERATOR)"
    cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 --private-key="${OPERATOR_SECRET}" \
      "${ram_address}" "grantRole(bytes32,address)" "${am_role}" "${DEPLOYER_ADDRESS}"
  fi
fi

# -- Optional: wire MockRewardsEligibilityOracle as RM's providerEligibilityOracle --
# REO_MOCK=1 (default in .env) replaces REO-A with the mock so tests can
# self-toggle eligibility (mock.setEligible(bool) signed by indexer's own key).
# REO_MOCK=0 keeps REO-A wired (production-like).
#
# Direct cast send rather than the deployment package's
# `RewardsEligibilityOracleMock,integrate` task because that task is missing
# the syncComponentsFromRegistry call its REO-A counterpart has, so it fails
# with "RewardsManager not deployed". See task notes for the upstream fix.
if [ "${REO_MOCK:-1}" = "1" ]; then
  rm_address=$(jq -r '.["1337"].RewardsManager.address // empty' /opt/config/horizon.json 2>/dev/null || true)
  mock_address=$(jq -r '.["1337"].RewardsEligibilityOracleMock.address // empty' /opt/config/issuance.json 2>/dev/null || true)
  if [ -z "${rm_address}" ] || [ -z "${mock_address}" ]; then
    echo "  REO_MOCK=1 set but RewardsManager or RewardsEligibilityOracleMock address missing — skipping wire"
  else
    current_oracle=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
      "${rm_address}" "getProviderEligibilityOracle()(address)" 2>/dev/null || echo "0x")
    current_lc=$(echo "$current_oracle" | tr '[:upper:]' '[:lower:]')
    target_lc=$(echo "$mock_address" | tr '[:upper:]' '[:lower:]')
    if [ "$current_lc" = "$target_lc" ]; then
      echo "  RewardsManager.providerEligibilityOracle already points at mock (${mock_address})"
    else
      echo "  Wiring RewardsManager.providerEligibilityOracle to mock ${mock_address} (was ${current_oracle})"
      cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 \
        --private-key="${GOVERNOR_SECRET}" \
        "${rm_address}" "setProviderEligibilityOracle(address)" "${mock_address}"
    fi
  fi
else
  echo "  REO_MOCK=0 — keeping RewardsEligibilityOracleA wired to RewardsManager"
fi

# Clean deployment metadata from address books.
# The deployment package writes fields like implementationDeployment and
# proxyDeployment that the indexer-agent doesn't recognise, causing it to
# crash with "Address book entry contains invalid fields".
for ab in horizon.json subgraph-service.json issuance.json; do
  if [ -f "/opt/config/$ab" ]; then
    TEMP_JSON=$(jq 'walk(if type == "object" then del(.implementationDeployment, .proxyDeployment) else . end)' "/opt/config/$ab")
    printf '%s\n' "$TEMP_JSON" > "/opt/config/$ab"
  fi
done

echo "==== Phase 3 complete ===="
fi  # GIP0088_ENABLED
echo "==== All contract deployments complete ===="

# Optional: keep container running for debugging
if [ -n "${KEEP_CONTAINER_RUNNING:-}" ]; then
  tail -f /dev/null
fi
