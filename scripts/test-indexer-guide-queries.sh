#!/bin/bash
# Layer 0: Validate all queries and cast commands from IndexerTestGuide.md
#
# Tests:
#   - GraphQL verification queries against network subgraph
#   - cast call commands against REO and RewardsManager contracts
#
# Prerequisites:
#   - Local network running with eligibility-oracle override
#   - REO contract deployed (Phase 4)
#   - `cast` available (Foundry)
#
# Usage: ./scripts/test-indexer-guide-queries.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../.env
. "$REPO_ROOT/.env"

# Ensure cast is on PATH
export PATH="$HOME/.foundry/bin:$PATH"

SUBGRAPH_URL="http://${GRAPH_NODE_HOST:-localhost}:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network"
RPC_URL="http://${CHAIN_HOST:-localhost}:${CHAIN_RPC_PORT}"
INDEXER=$(echo "$RECEIVER_ADDRESS" | tr '[:upper:]' '[:lower:]')

pass=0
fail=0
total=0

# -- Helpers --
run_query() {
  local label="$1"
  local query="$2"
  total=$((total + 1))

  result=$(curl -s --max-time 10 "$SUBGRAPH_URL" \
    -H 'content-type: application/json' \
    -d "{\"query\": \"$query\"}" 2>&1)

  if echo "$result" | grep -q '"errors"'; then
    echo "  FAIL  $label"
    echo "        $(echo "$result" | jq -r '.errors[0].message' 2>/dev/null || echo "$result")"
    fail=$((fail + 1))
    return 1
  elif echo "$result" | grep -q '"data"'; then
    echo "  PASS  $label"
    pass=$((pass + 1))
    return 0
  else
    echo "  FAIL  $label (no data or errors in response)"
    echo "        $result"
    fail=$((fail + 1))
    return 1
  fi
}

run_cast() {
  local label="$1"
  shift
  total=$((total + 1))

  if result=$("$@" 2>&1); then
    echo "  PASS  $label"
    echo "        → $result"
    pass=$((pass + 1))
    return 0
  else
    echo "  FAIL  $label"
    echo "        $result"
    fail=$((fail + 1))
    return 1
  fi
}

echo "=== IndexerTestGuide Query & Command Validation ==="
echo "  Subgraph: $SUBGRAPH_URL"
echo "  RPC:      $RPC_URL"
echo "  Indexer:  $INDEXER"
echo ""

# -- Resolve REO contract address --
REO_ADDRESS=$(docker exec graph-node cat /opt/config/issuance.json 2>/dev/null \
  | jq -r '.["1337"].RewardsEligibilityOracle.address // empty' 2>/dev/null || true)

if [ -z "$REO_ADDRESS" ]; then
  echo "  WARNING: REO contract not found. Skipping cast tests."
  echo "  Is the eligibility-oracle override active?"
  SKIP_CAST=true
else
  echo "  REO:      $REO_ADDRESS"
  SKIP_CAST=false
fi

# -- Resolve RewardsManager address --
REWARDS_MANAGER=$(docker exec graph-node cat /opt/config/horizon.json 2>/dev/null \
  | jq -r '.["1337"].RewardsManager.address // empty' 2>/dev/null || true)

if [ -n "$REWARDS_MANAGER" ]; then
  echo "  RM:       $REWARDS_MANAGER"
fi
echo ""

# ============================================================
# GraphQL Queries
# ============================================================
echo "--- GraphQL Queries ---"

run_query "1.1 Indexer allocations (singular)" \
  "{ indexer(id: \\\"$INDEXER\\\") { allocations(where: { status: \\\"Active\\\" }) { id subgraphDeployment { ipfsHash } allocatedTokens createdAtEpoch } } graphNetwork(id: \\\"1\\\") { currentEpoch } }" || true

ALLOC_ID=$(curl -s "$SUBGRAPH_URL" \
  -H 'content-type: application/json' \
  -d "{\"query\": \"{ allocations(first: 1, where: { indexer_: { id: \\\"$INDEXER\\\" } }) { id } }\"}" \
  | jq -r '.data.allocations[0].id // empty' 2>/dev/null || true)
ALLOC_ID="${ALLOC_ID:-0x0000000000000000000000000000000000000000}"

run_query "2.2 Allocation close verification" \
  "{ allocations(where: { id: \\\"$ALLOC_ID\\\" }) { id status indexingRewards closedAtEpoch } }" || true

run_query "4.2 Allocation with epochs" \
  "{ allocations(where: { id: \\\"$ALLOC_ID\\\" }) { id status indexingRewards createdAtEpoch closedAtEpoch } }" || true

echo ""

# ============================================================
# Cast Commands (contract calls)
# ============================================================
echo "--- Contract Calls (cast) ---"

if [ "$SKIP_CAST" = "true" ]; then
  echo "  SKIP  (REO contract not deployed)"
  echo ""
else
  run_cast "Prereq: getEligibilityValidation" \
    cast call --rpc-url="$RPC_URL" "$REO_ADDRESS" "getEligibilityValidation()(bool)" || true

  run_cast "Prereq: getEligibilityPeriod" \
    cast call --rpc-url="$RPC_URL" "$REO_ADDRESS" "getEligibilityPeriod()(uint256)" || true

  ORACLE_ROLE=$(cast keccak "ORACLE_ROLE" 2>/dev/null || true)
  if [ -n "$ORACLE_ROLE" ]; then
    run_cast "Prereq: hasRole(ORACLE_ROLE, indexer)" \
      cast call --rpc-url="$RPC_URL" "$REO_ADDRESS" "hasRole(bytes32,address)(bool)" "$ORACLE_ROLE" "$INDEXER" || true
  fi

  run_cast "2.1 isEligible" \
    cast call --rpc-url="$RPC_URL" "$REO_ADDRESS" "isEligible(address)(bool)" "$INDEXER" || true

  run_cast "2.1 getEligibilityRenewalTime" \
    cast call --rpc-url="$RPC_URL" "$REO_ADDRESS" "getEligibilityRenewalTime(address)(uint256)" "$INDEXER" || true

  run_cast "3.1 block timestamp" \
    cast block latest --field timestamp --rpc-url="$RPC_URL" || true

  run_cast "Troubleshoot: paused" \
    cast call --rpc-url="$RPC_URL" "$REO_ADDRESS" "paused()(bool)" || true

  if [ -n "$REWARDS_MANAGER" ]; then
    run_cast "Troubleshoot: getRewardsEligibilityOracle" \
      cast call --rpc-url="$RPC_URL" "$REWARDS_MANAGER" "getRewardsEligibilityOracle()(address)" || true
  fi

  echo ""
fi

# ============================================================
# Summary
# ============================================================
echo "=== Results ==="
echo "  $pass passed, $fail failed, $total total"

if [ "$fail" -eq 0 ]; then
  echo "  All queries and commands valid."
  exit 0
else
  echo "  Some queries or commands failed. Check output above."
  exit 1
fi
