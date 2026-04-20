#!/bin/bash
# test-query-fees.sh — Validate continuous RAV collection on a single allocation.
#
# Tests that RAVs can be created and collected on-chain multiple times on the
# same allocation without closing it. Validates the continuous collection design
# for Horizon's long-lived allocations.
#
# Verification uses the network subgraph's graphTallyTokensCollecteds entity
# to confirm on-chain collection (not redeemed_at, which stays null for active
# allocations in the continuous collection design).
#
# Prerequisites:
#   - local-network is running (docker compose up -d)
#   - At least one subgraph deployed with an active allocation
#   - indexer-agent configured with --rav-collection-interval=60 --rav-check-interval=30
#
# Usage:
#   ./scripts/test-query-fees.sh [SUBGRAPH_ID]
#
# If SUBGRAPH_ID is not provided, uses $SUBGRAPH from .env.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../.env
. "$REPO_ROOT/.env"
[ -f "$REPO_ROOT/.env.local" ] && . "$REPO_ROOT/.env.local"

# --- Configuration ---
AGENT_URL="http://${INDEXER_AGENT_HOST:-localhost}:${INDEXER_MANAGEMENT_PORT:-7600}"
PG_HOST="${POSTGRES_HOST:-localhost}"
PG_PORT="${POSTGRES_PORT:-5432}"
PG_DB="indexer_components_1"
PG_USER="postgres"
PGPASSWORD="${POSTGRES_PASSWORD:-}" ; export PGPASSWORD

HARDHAT_RPC="http://${CHAIN_HOST:-localhost}:${CHAIN_RPC_PORT:-8545}"
NETWORK_SUBGRAPH_URL="http://${GRAPH_NODE_HOST:-localhost}:${GRAPH_NODE_QUERY_PORT:-8000}/subgraphs/name/graph-network"
INDEXER_ADDRESS="${RECEIVER_ADDRESS:?Set RECEIVER_ADDRESS in .env}"

# Contract addresses (discovered from config files inside the indexer-agent container)
GRAPH_TALLY_COLLECTOR=$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['GraphTallyCollector']['address'])" 2>/dev/null)
PAYMENTS_ESCROW=$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['PaymentsEscrow']['address'])" 2>/dev/null)
GRT_TOKEN=$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['L2GraphToken']['address'])" 2>/dev/null)
PAYER_ADDRESS="${ACCOUNT0_ADDRESS:?Set ACCOUNT0_ADDRESS in .env}"
PAYER_SECRET="${ACCOUNT0_SECRET:?Set ACCOUNT0_SECRET in .env}"

SUBGRAPH_ID="${1:-${SUBGRAPH:-}}"
QUERY_COUNT=3000
TRIGGER_COUNT=1
RAV_CYCLES=2
POLL_INTERVAL=5
RAV_CREATION_TIMEOUT=180
RAV_REDEMPTION_TIMEOUT=180

# --- Counters ---
pass=0
fail=0
total=0

# --- Helpers ---

pgcmd() {
  psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" -tAq "$@"
}

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

# Convert allocation ID to collection_id format used in tap_horizon_ravs.
# collection_id is allocation address without 0x prefix, lowercased, zero-padded to 64 chars.
alloc_to_collection_id() {
  local alloc_id="${1#0x}"
  printf '%064s' "$alloc_id" | tr ' ' '0' | tr '[:upper:]' '[:lower:]'
}

# Resolve subgraph ID -> deployment IPFS hash via network subgraph
resolve_deployment() {
  local subgraph_id="$1"
  curl -s "$NETWORK_SUBGRAPH_URL" \
    -H 'content-type: application/json' \
    -d "{\"query\": \"{ subgraphs(where: { id: \\\"$subgraph_id\\\" }) { currentVersion { subgraphDeployment { ipfsHash } } } }\"}" \
    | jq -r '.data.subgraphs[0].currentVersion.subgraphDeployment.ipfsHash // empty'
}

# Find active allocation for a specific deployment
find_allocation_for_deployment() {
  local ipfs="$1"
  gql "$AGENT_URL" "{ allocations(filter: {}) { id subgraphDeployment status } }" \
    | jq -r --arg d "$ipfs" '[.data.allocations[] | select(.status == "Active" and .subgraphDeployment == $d)][0].id // empty'
}

# Query on-chain tokens collected for a collection ID via network subgraph.
# Returns the tokens value (wei string) or "0" if not found.
get_tokens_collected() {
  local collection_id="$1"
  local indexer="${INDEXER_ADDRESS,,}"  # lowercase
  local collection_id_hex="0x$collection_id"

  local result
  result=$(curl -s --max-time 10 "$NETWORK_SUBGRAPH_URL" \
    -H 'content-type: application/json' \
    -d "{\"query\": \"{ graphTallyTokensCollecteds(where: { collectionId: \\\"$collection_id_hex\\\", receiver_: { id: \\\"$indexer\\\" }}) { tokens } }\"}" \
    2>/dev/null)

  echo "$result" | jq -r '.data.graphTallyTokensCollecteds[0].tokens // "0"'
}

# Get latest RAV updated_at for an allocation.
# Uses updated_at because in Horizon the tap-agent updates existing RAVs
# in-place (value_aggregate increases) rather than creating new rows.
get_latest_rav_timestamp() {
  local collection_id="$1"
  pgcmd -c "SELECT COALESCE(MAX(updated_at), '1970-01-01') FROM tap_horizon_ravs WHERE collection_id = '$collection_id'" \
    2>/dev/null || echo "1970-01-01"
}

# Mine blocks and wait for network subgraph to sync.
# Targets the network subgraph specifically (not min across all subgraphs,
# which could stall if any unrelated subgraph is behind).
mine_and_sync() {
  local blocks="${1:-5}"

  # Mine blocks to advance chain and give subgraph something to index
  "$SCRIPT_DIR/mine-block.sh" "$blocks" > /dev/null 2>&1

  # Wait for network subgraph to catch up (up to 30s)
  local start_ts=$(date +%s)
  local elapsed=0
  while [ "$elapsed" -lt 30 ]; do
    local chain_head subgraph_head
    chain_head=$(curl -sf "$HARDHAT_RPC" \
      -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
      | jq -r '.result' | xargs printf '%d' 2>/dev/null || echo "0")

    # Query the network subgraph's _meta for its latest indexed block
    subgraph_head=$(curl -s --max-time 5 "$NETWORK_SUBGRAPH_URL" \
      -H 'content-type: application/json' \
      -d '{"query": "{ _meta { block { number } } }"}' \
      | jq -r '.data._meta.block.number // 0' 2>/dev/null || echo "0")

    if [ "$subgraph_head" -ge "$((chain_head - 1))" ] 2>/dev/null; then
      return 0
    fi
    sleep 2
    elapsed=$(( $(date +%s) - start_ts ))
  done
  echo "  [!] Subgraph sync timed out (chain=$chain_head, subgraph=$subgraph_head)"
}

# Dump diagnostic info for debugging failures
dump_diagnostics() {
  local collection_id="$1"
  echo "  --- Diagnostics ---"

  # Check RAV rows in DB
  local rav_count
  rav_count=$(pgcmd -c "SELECT COUNT(*) FROM tap_horizon_ravs WHERE collection_id = '$collection_id'" 2>/dev/null || echo "error")
  echo "  RAV rows in DB for collection: $rav_count"

  # Check RAV details
  pgcmd -c "SELECT value_aggregate, last, final, redeemed_at, created_at FROM tap_horizon_ravs WHERE collection_id = '$collection_id' ORDER BY created_at DESC LIMIT 3" 2>/dev/null || echo "  (could not query RAVs)"

  # Check on-chain collected tokens
  local collected
  collected=$(get_tokens_collected "$collection_id")
  echo "  On-chain tokens collected: $collected"

  # Check receipt count (Horizon tap receipts that feed into RAVs)
  local receipt_count
  receipt_count=$(pgcmd -c "SELECT COUNT(*) FROM tap_horizon_receipts" 2>/dev/null || echo "error")
  echo "  Total Horizon tap receipts in DB: $receipt_count"

  echo "  --- End Diagnostics ---"
}

# Poll for new RAV after a given timestamp
poll_for_new_rav() {
  local collection_id="$1"
  local after_timestamp="$2"
  local timeout="${3:-$RAV_CREATION_TIMEOUT}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout" ]; do
    local count
    count=$(pgcmd -c "SELECT COUNT(*) FROM tap_horizon_ravs WHERE collection_id = '$collection_id' AND updated_at > '$after_timestamp'" \
      2>/dev/null || echo "0")
    if [ "$count" -gt 0 ]; then
      echo "  [+] RAV updated after $after_timestamp"
      return 0
    fi
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
  done
  echo "  [-] Timed out waiting for new RAV (${timeout}s)"
  return 1
}

# Poll for on-chain collection to happen (tokens collected increases).
# This replaces the old redeemed_at check since active-allocation RAVs
# don't get redeemed_at set in the continuous collection design.
poll_for_collection() {
  local collection_id="$1"
  local initial_collected="$2"
  local timeout="${3:-$RAV_REDEMPTION_TIMEOUT}"
  local start_ts=$(date +%s)

  while true; do
    local elapsed=$(( $(date +%s) - start_ts ))
    if [ "$elapsed" -ge "$timeout" ]; then
      echo "  [-] Timed out waiting for on-chain collection (${timeout}s)"
      return 1
    fi

    # Mine blocks so collection tx gets indexed by the subgraph
    mine_and_sync 3

    local current_collected
    current_collected=$(get_tokens_collected "$collection_id")

    # Compare as strings — both are wei values from the subgraph.
    # initial_collected is "0" on first run; after collection it becomes a non-zero wei string.
    if [ "$current_collected" != "0" ] && [ "$current_collected" != "$initial_collected" ]; then
      echo "  [+] On-chain collection detected (tokens: $initial_collected -> $current_collected)"
      return 0
    fi
    sleep "$POLL_INTERVAL"
  done
}

# --- Prerequisites ---
echo "=== Prerequisites ==="
echo "Checking database connection..."
pgcmd -c 'SELECT 1;' > /dev/null || { echo "FAIL: Cannot connect to database"; exit 1; }
echo "Checking agent health..."
gql "$AGENT_URL" "{ indexingRules(merged: false) { identifier } }" | jq -e '.data' > /dev/null || { echo "FAIL: Agent not responding"; exit 1; }

if [ -z "$SUBGRAPH_ID" ]; then
  echo "FAIL: No SUBGRAPH_ID provided and \$SUBGRAPH not set in .env"
  exit 1
fi

echo "Ensuring cost model is set (gateway needs non-zero fees to generate receipts)..."
gql "$AGENT_URL" "mutation { setCostModel(costModel: { deployment: \\\"global\\\", model: \\\"default => 0.00004;\\\" }) { deployment } }" | jq -e '.data' > /dev/null || { echo "FAIL: Could not set cost model"; exit 1; }

echo "Ensuring payer escrow is funded..."
escrow_balance=$(cast call --rpc-url "$HARDHAT_RPC" \
  "$PAYMENTS_ESCROW" "getBalance(address,address,address)(uint256)" \
  "$PAYER_ADDRESS" "$INDEXER_ADDRESS" "$GRAPH_TALLY_COLLECTOR" 2>/dev/null || echo "0")
if [ "$escrow_balance" = "0" ]; then
  echo "  Depositing 1000 GRT escrow..."
  ESCROW_AMOUNT="1000000000000000000000"
  cast send --rpc-url "$HARDHAT_RPC" --private-key "$PAYER_SECRET" \
    "$GRT_TOKEN" "approve(address,uint256)" "$PAYMENTS_ESCROW" "$ESCROW_AMOUNT" > /dev/null 2>&1
  cast send --rpc-url "$HARDHAT_RPC" --private-key "$PAYER_SECRET" \
    "$PAYMENTS_ESCROW" "deposit(address,address,uint256)" "$INDEXER_ADDRESS" "$GRAPH_TALLY_COLLECTOR" "$ESCROW_AMOUNT" > /dev/null 2>&1
  echo "  Escrow deposited"
else
  echo "  Escrow already funded: $escrow_balance"
fi

echo "Prerequisites OK"
echo

# --- Setup ---
echo "=== Setup ==="
echo "Subgraph ID: $SUBGRAPH_ID"

DEPLOYMENT_IPFS=$(resolve_deployment "$SUBGRAPH_ID")
if [ -z "$DEPLOYMENT_IPFS" ]; then
  echo "FAIL: Could not resolve deployment for subgraph $SUBGRAPH_ID"
  exit 1
fi
echo "Deployment: $DEPLOYMENT_IPFS"

ALLOC_ID=$(find_allocation_for_deployment "$DEPLOYMENT_IPFS")
if [ -z "$ALLOC_ID" ]; then
  echo "FAIL: No active allocation for deployment $DEPLOYMENT_IPFS"
  exit 1
fi
echo "Allocation: $ALLOC_ID"

COLLECTION_ID=$(alloc_to_collection_id "$ALLOC_ID")
echo "Collection ID: $COLLECTION_ID"

initial_collected=$(get_tokens_collected "$COLLECTION_ID")
echo "Tokens already collected for this allocation: $initial_collected"
echo

# --- RAV Cycles ---
for cycle in $(seq 1 "$RAV_CYCLES"); do
  echo "=== RAV Cycle $cycle/$RAV_CYCLES ==="

  rav_before=$(get_latest_rav_timestamp "$COLLECTION_ID")
  collected_before=$(get_tokens_collected "$COLLECTION_ID")

  echo "Tokens collected before cycle: $collected_before"

  echo "Sending $QUERY_COUNT queries to accumulate fees..."
  "$SCRIPT_DIR/query_gateway.sh" "$QUERY_COUNT" "$SUBGRAPH_ID" > /dev/null 2>&1

  echo "Waiting 20s for receipts to be processed..."
  sleep 20

  echo "Sending $TRIGGER_COUNT query to trigger RAV creation..."
  "$SCRIPT_DIR/query_gateway.sh" "$TRIGGER_COUNT" "$SUBGRAPH_ID" > /dev/null 2>&1

  echo "Waiting for RAV creation..."
  if ! poll_for_new_rav "$COLLECTION_ID" "$rav_before"; then
    echo "FAIL: RAV not created in cycle $cycle"
    dump_diagnostics "$COLLECTION_ID"
    exit 1
  fi

  echo "Mining blocks to advance time and trigger collection loop..."
  mine_and_sync 10

  echo "Waiting for on-chain collection..."
  if ! poll_for_collection "$COLLECTION_ID" "$collected_before"; then
    echo "FAIL: On-chain collection did not happen in cycle $cycle"
    dump_diagnostics "$COLLECTION_ID"
    exit 1
  fi

  # Verify allocation still active
  current_alloc=$(find_allocation_for_deployment "$DEPLOYMENT_IPFS")
  check "Allocation still active after cycle $cycle" "[ '$current_alloc' = '$ALLOC_ID' ]"

  echo "Cycle $cycle PASSED"
  echo
done

# --- Final Verification ---
echo "=== Final Verification ==="
final_alloc=$(find_allocation_for_deployment "$DEPLOYMENT_IPFS")
check "Allocation unchanged throughout test" "[ '$final_alloc' = '$ALLOC_ID' ]"

final_collected=$(get_tokens_collected "$COLLECTION_ID")
check "Tokens were collected on-chain" "[ '$final_collected' != '0' ]"

echo
echo "=== Results: $pass/$total passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
  exit 1
fi
echo "Query fees collected continuously without closing the allocation."
