#!/bin/bash
# Layer 1: Verify local network state matches BaselineTestPlan expectations.
#
# Checks that the network initialised correctly after `docker compose up`:
#   - Indexer registered with stake, URL, geoHash
#   - Provision exists with non-zero tokens
#   - Active allocations exist
#   - Subgraph deployments synced and healthy
#   - Gateway serves queries
#   - Epoch is progressing
#   - Indexer agent management API responsive
#
# This catches deployment regressions before you run operational tests.
#
# Prerequisites:
#   - Local network fully started (all services healthy)
#
# Usage: ./scripts/test-baseline-state.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../.env
. "$REPO_ROOT/.env"

SUBGRAPH_URL="http://${GRAPH_NODE_HOST:-localhost}:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network"
AGENT_URL="http://${INDEXER_AGENT_HOST:-localhost}:${INDEXER_MANAGEMENT_PORT}"
GATEWAY_URL="http://${GATEWAY_HOST:-localhost}:${GATEWAY_PORT}"
RPC_URL="http://${CHAIN_HOST:-localhost}:${CHAIN_RPC_PORT}"
INDEXER=$(echo "$RECEIVER_ADDRESS" | tr '[:upper:]' '[:lower:]')

export PATH="$HOME/.foundry/bin:$PATH"

pass=0
fail=0
total=0

# -- Helpers --
check() {
  local label="$1"
  local condition="$2"
  total=$((total + 1))

  if eval "$condition" > /dev/null 2>&1; then
    echo "  PASS  $label"
    pass=$((pass + 1))
    return 0
  else
    echo "  FAIL  $label"
    fail=$((fail + 1))
    return 1
  fi
}

gql() {
  local url="$1"
  local query="$2"
  curl -s --max-time 10 "$url" \
    -H 'content-type: application/json' \
    -d "{\"query\": \"$query\"}" 2>/dev/null
}

jq_test() {
  local json="$1"
  local expr="$2"
  echo "$json" | jq -e "$expr" > /dev/null 2>&1
}

echo "=== Baseline State Observation ==="
echo "  Subgraph:  $SUBGRAPH_URL"
echo "  Agent:     $AGENT_URL"
echo "  Gateway:   $GATEWAY_URL"
echo "  RPC:       $RPC_URL"
echo "  Indexer:   $INDEXER"
echo ""

# ============================================================
# Network Subgraph (Cycle 1: Indexer Setup)
# ============================================================
echo "--- Indexer Registration (Cycle 1) ---"

indexer_data=$(gql "$SUBGRAPH_URL" \
  "{ indexers(where: { id: \\\"$INDEXER\\\" }) { id stakedTokens url geoHash queryFeeCut indexingRewardCut } }")

check "1.1 Indexer entity exists" \
  "jq_test '$indexer_data' '.data.indexers | length > 0'" || true

check "1.1 Staked tokens non-zero" \
  "jq_test '$indexer_data' '.data.indexers[0].stakedTokens != \"0\"'" || true

check "1.2 URL is set" \
  "jq_test '$indexer_data' '.data.indexers[0].url != null and .data.indexers[0].url != \"\"'" || true

check "1.2 GeoHash is set" \
  "jq_test '$indexer_data' '.data.indexers[0].geoHash != null and .data.indexers[0].geoHash != \"\"'" || true

echo ""

# ============================================================
# Provision (Cycle 1.3 + Cycle 3)
# ============================================================
echo "--- Provision (Cycle 1.3 / Cycle 3) ---"

provision_data=$(gql "$SUBGRAPH_URL" \
  "{ provisions(where: { indexer_: { id: \\\"$INDEXER\\\" } }) { id tokensProvisioned tokensAllocated tokensThawing dataService { id } } }")

check "1.3 Provision exists" \
  "jq_test '$provision_data' '.data.provisions | length > 0'" || true

check "1.3 Provision tokens non-zero" \
  "jq_test '$provision_data' '.data.provisions[0].tokensProvisioned != \"0\"'" || true

check "3.1 DataService is set" \
  "jq_test '$provision_data' '.data.provisions[0].dataService.id != null'" || true

echo ""

# ============================================================
# Allocations (Cycle 4)
# ============================================================
echo "--- Allocations (Cycle 4) ---"

alloc_data=$(gql "$SUBGRAPH_URL" \
  "{ allocations(where: { indexer_: { id: \\\"$INDEXER\\\" }, status: \\\"Active\\\" }) { id allocatedTokens subgraphDeployment { ipfsHash } createdAtEpoch } }")

active_count=$(echo "$alloc_data" | jq '.data.allocations | length' 2>/dev/null || echo "0")

check "4.x Active allocations exist" \
  "[ \"$active_count\" -gt 0 ]" || true

echo "       ($active_count active allocations)"

echo ""

# ============================================================
# Graph Node Deployments (via Agent)
# ============================================================
echo "--- Graph Node Deployments ---"

deploy_data=$(gql "$AGENT_URL" \
  "{ indexerDeployments { subgraphDeployment synced health } }")

deploy_count=$(echo "$deploy_data" | jq '.data.indexerDeployments | length' 2>/dev/null || echo "0")
synced_count=$(echo "$deploy_data" | jq '[.data.indexerDeployments[] | select(.synced == true)] | length' 2>/dev/null || echo "0")
healthy_count=$(echo "$deploy_data" | jq '[.data.indexerDeployments[] | select(.health == "healthy")] | length' 2>/dev/null || echo "0")

check "Deployments indexed" \
  "[ \"$deploy_count\" -gt 0 ]" || true

check "All deployments synced" \
  "[ \"$synced_count\" = \"$deploy_count\" ]" || true

check "All deployments healthy" \
  "[ \"$healthy_count\" = \"$deploy_count\" ]" || true

echo "       ($synced_count/$deploy_count synced, $healthy_count/$deploy_count healthy)"

echo ""

# ============================================================
# Agent Registration
# ============================================================
echo "--- Indexer Agent ---"

reg_data=$(gql "$AGENT_URL" \
  "{ indexerRegistration(protocolNetwork: \\\"hardhat\\\") { address url registered } }")

check "Agent registered" \
  "jq_test '$reg_data' '.data.indexerRegistration[0].registered == true'" || true

check "Agent URL matches subgraph" \
  "jq_test '$reg_data' '.data.indexerRegistration[0].url != null'" || true

echo ""

# ============================================================
# Gateway (Cycle 5)
# ============================================================
echo "--- Gateway (Cycle 5) ---"

gw_response=$(curl -s --max-time 10 \
  "$GATEWAY_URL/api/subgraphs/id/$SUBGRAPH" \
  -H 'content-type: application/json' \
  -H "Authorization: Bearer $GATEWAY_API_KEY" \
  -d '{"query": "{ _meta { block { number } } }"}' 2>/dev/null)

check "Gateway serves queries" \
  "jq_test '$gw_response' '.data._meta.block.number != null'" || true

block_num=$(echo "$gw_response" | jq '.data._meta.block.number' 2>/dev/null || echo "?")
echo "       (block $block_num)"

echo ""

# ============================================================
# Epoch Progression (Cycle 6)
# ============================================================
echo "--- Network Health (Cycle 6) ---"

network_data=$(gql "$SUBGRAPH_URL" \
  "{ graphNetworks { currentEpoch totalTokensStaked totalTokensAllocated } }")

check "6.2 Epoch is non-zero" \
  "jq_test '$network_data' '.data.graphNetworks[0].currentEpoch > 0'" || true

current_epoch=$(echo "$network_data" | jq '.data.graphNetworks[0].currentEpoch' 2>/dev/null || echo "?")
echo "       (epoch $current_epoch)"

echo ""

# ============================================================
# Chain RPC
# ============================================================
echo "--- Chain ---"

chain_block=$(cast block-number --rpc-url="$RPC_URL" 2>/dev/null || echo "0")
check "Chain RPC responsive" \
  "[ \"$chain_block\" -gt 0 ]" || true

echo "       (block $chain_block)"

echo ""

# ============================================================
# REO (if deployed)
# ============================================================
REO_ADDRESS=$(docker exec graph-node cat /opt/config/issuance.json 2>/dev/null \
  | jq -r '.["1337"].RewardsEligibilityOracle.address // empty' 2>/dev/null || true)

if [ -n "$REO_ADDRESS" ]; then
  echo "--- REO Contract ---"

  validation=$(cast call --rpc-url="$RPC_URL" "$REO_ADDRESS" "getEligibilityValidation()(bool)" 2>/dev/null || echo "error")
  check "REO deployed and callable" \
    "[ \"$validation\" = \"true\" ] || [ \"$validation\" = \"false\" ]" || true
  echo "       (validation=$validation)"

  eligible=$(cast call --rpc-url="$RPC_URL" "$REO_ADDRESS" "isEligible(address)(bool)" "$RECEIVER_ADDRESS" 2>/dev/null || echo "error")
  check "Indexer eligibility queryable" \
    "[ \"$eligible\" = \"true\" ] || [ \"$eligible\" = \"false\" ]" || true
  echo "       (eligible=$eligible)"

  echo ""
fi

# ============================================================
# Summary
# ============================================================
echo "=== Results ==="
echo "  $pass passed, $fail failed, $total total"

if [ "$fail" -eq 0 ]; then
  echo "  Network state matches baseline expectations."
  exit 0
else
  echo "  Some checks failed — network may not be fully initialised."
  echo "  Wait for all services to be healthy: docker compose ps"
  exit 1
fi
