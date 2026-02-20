#!/bin/bash
# Layer 0: Validate all GraphQL verification queries from BaselineTestPlan.md
#
# Runs each query against the network subgraph with real local network values.
# Checks for GraphQL errors — does NOT verify operational outcomes.
#
# Prerequisites:
#   - Local network running (graph-node, indexer-agent with allocations)
#   - Network subgraph deployed and synced
#
# Usage: ./scripts/test-baseline-queries.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../.env
. "$REPO_ROOT/.env"

SUBGRAPH_URL="http://${GRAPH_NODE_HOST:-localhost}:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network"
INDEXER=$(echo "$RECEIVER_ADDRESS" | tr '[:upper:]' '[:lower:]')

pass=0
fail=0
total=0

# -- Helper --
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

echo "=== BaselineTestPlan Query Validation ==="
echo "  Subgraph: $SUBGRAPH_URL"
echo "  Indexer:  $INDEXER"
echo ""

# -- Resolve dynamic values --
# Get first allocation ID for queries that need it
ALLOC_ID=$(curl -s "$SUBGRAPH_URL" \
  -H 'content-type: application/json' \
  -d "{\"query\": \"{ allocations(first: 1, where: { indexer_: { id: \\\"$INDEXER\\\" } }) { id subgraphDeployment { ipfsHash } } }\"}" \
  | jq -r '.data.allocations[0].id // empty' 2>/dev/null || true)

DEPLOYMENT=$(curl -s "$SUBGRAPH_URL" \
  -H 'content-type: application/json' \
  -d "{\"query\": \"{ allocations(first: 1, where: { indexer_: { id: \\\"$INDEXER\\\" } }) { subgraphDeployment { ipfsHash } } }\"}" \
  | jq -r '.data.allocations[0].subgraphDeployment.ipfsHash // empty' 2>/dev/null || true)

if [ -z "$ALLOC_ID" ]; then
  echo "  WARNING: No allocations found for indexer. Some queries will use placeholder values."
  ALLOC_ID="0x0000000000000000000000000000000000000000"
fi
if [ -z "$DEPLOYMENT" ]; then
  DEPLOYMENT="QmUnknown"
fi

echo "  Allocation: $ALLOC_ID"
echo "  Deployment: $DEPLOYMENT"
echo ""

# ============================================================
# Cycle 1: Indexer Setup and Registration
# ============================================================
echo "--- Cycle 1: Indexer Setup and Registration ---"

run_query "1.1 Indexer setup" \
  "{ indexers(where: { id: \\\"$INDEXER\\\" }) { id createdAt stakedTokens queryFeeCut indexingRewardCut } }" || true

run_query "1.2 Indexer URL/GEO" \
  "{ indexers(where: { id: \\\"$INDEXER\\\" }) { id url geoHash } }" || true

run_query "1.3 SubgraphService provision" \
  "{ provisions(where: { indexer_: { id: \\\"$INDEXER\\\" } }) { id indexer { id url geoHash } tokensProvisioned tokensAllocated tokensThawing thawingPeriod maxVerifierCut dataService { id } } }" || true

echo ""

# ============================================================
# Cycle 2: Stake Management
# ============================================================
echo "--- Cycle 2: Stake Management ---"

run_query "2.1 Stake view" \
  "{ indexers(where: { id: \\\"$INDEXER\\\" }) { id stakedTokens allocatedTokens availableStake } }" || true

run_query "2.2 Thaw requests" \
  "{ indexers(where: { id: \\\"$INDEXER\\\" }) { id stakedTokens availableStake } thawRequests(where: { indexer_: { id: \\\"$INDEXER\\\" } }) { id tokens thawingUntil type } }" || true

echo ""

# ============================================================
# Cycle 3: Provision Management
# ============================================================
echo "--- Cycle 3: Provision Management ---"

run_query "3.1 View provision" \
  "{ provisions(where: { indexer_: { id: \\\"$INDEXER\\\" } }) { id tokensProvisioned tokensThawing tokensAllocated thawingPeriod maxVerifierCut } }" || true

run_query "3.2 Provision + indexer stake" \
  "{ provisions(where: { indexer_: { id: \\\"$INDEXER\\\" } }) { id tokensProvisioned tokensAllocated indexer { stakedTokens availableStake } } }" || true

run_query "3.3 Provision + thawRequests (enum filter)" \
  "{ provisions(where: { indexer_: { id: \\\"$INDEXER\\\" } }) { id tokensProvisioned tokensThawing } thawRequests(where: { indexer_: { id: \\\"$INDEXER\\\" }, type: Provision }) { id tokens thawingUntil } }" || true

run_query "3.4 Provision + indexer availableStake" \
  "{ provisions(where: { indexer_: { id: \\\"$INDEXER\\\" } }) { id tokensProvisioned tokensThawing } indexers(where: { id: \\\"$INDEXER\\\" }) { availableStake } }" || true

echo ""

# ============================================================
# Cycle 4: Allocation Management
# ============================================================
echo "--- Cycle 4: Allocation Management ---"

run_query "4.1 Deployments with rewards" \
  "{ subgraphDeployments(where: { deniedAt: 0, signalledTokens_not: 0, indexingRewardAmount_not: 0 }) { ipfsHash stakedTokens signalledTokens indexingRewardAmount manifest { network } } }" || true

run_query "4.2 Active allocations" \
  "{ allocations(where: { indexer_: { id: \\\"$INDEXER\\\" }, status: \\\"Active\\\" }) { id allocatedTokens createdAtEpoch subgraphDeployment { ipfsHash } } }" || true

run_query "4.5 Allocations by deployment" \
  "{ allocations(where: { indexer_: { id: \\\"$INDEXER\\\" }, subgraphDeployment_: { ipfsHash: \\\"$DEPLOYMENT\\\" } }) { id status allocatedTokens createdAtEpoch closedAtEpoch } }" || true

echo ""

# ============================================================
# Cycle 5: Query Serving and Revenue
# ============================================================
echo "--- Cycle 5: Query Serving and Revenue ---"

run_query "5.2 Epoch + active allocations" \
  "{ graphNetworks { currentEpoch } allocations(where: { indexer_: { id: \\\"$INDEXER\\\" }, status: \\\"Active\\\" }) { id allocatedTokens createdAtEpoch } }" || true

run_query "5.2b Closed allocation rewards" \
  "{ allocations(where: { id: \\\"$ALLOC_ID\\\" }) { id status allocatedTokens indexingRewards closedAtEpoch } }" || true

run_query "5.3 Query fees collected" \
  "{ allocations(where: { indexer_: { id: \\\"$INDEXER\\\" }, status: \\\"Closed\\\" }) { id queryFeesCollected closedAtEpoch } }" || true

run_query "5.4 Allocation POI" \
  "{ allocations(where: { id: \\\"$ALLOC_ID\\\" }) { id status indexingRewards poi } }" || true

echo ""

# ============================================================
# Cycle 6: Network Health
# ============================================================
echo "--- Cycle 6: Network Health ---"

run_query "6.1 Indexer health" \
  "{ indexers(where: { id: \\\"$INDEXER\\\" }) { id url geoHash stakedTokens allocatedTokens availableStake delegatedTokens queryFeesCollected rewardsEarned allocations(where: { status: \\\"Active\\\" }) { id subgraphDeployment { ipfsHash } } } }" || true

run_query "6.2 Epoch progression" \
  "{ graphNetworks { id currentEpoch totalTokensStaked totalTokensAllocated totalQueryFees totalIndexingRewards } }" || true

echo ""

# ============================================================
# Summary
# ============================================================
echo "=== Results ==="
echo "  $pass passed, $fail failed, $total total"

if [ "$fail" -eq 0 ]; then
  echo "  All queries valid."
  exit 0
else
  echo "  Some queries have schema errors. Fix the test plan or subgraph."
  exit 1
fi
