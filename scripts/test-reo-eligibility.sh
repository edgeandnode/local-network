#!/bin/bash
# Test the Rewards Eligibility Oracle (REO) end-to-end cycle.
#
# Demonstrates: indexer NOT eligible → gateway queries → REO evaluates → indexer IS eligible
#
# Prerequisites:
#   - Local network running with eligibility-oracle override
#   - REO contract deployed (Phase 4 in graph-contracts)
#   - REO node running and connected to Redpanda
#   - `cast` available (Foundry)
#
# Usage: ./scripts/test-reo-eligibility.sh [query_count]
#   query_count: number of gateway queries to send (default: 10)
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load environment
# shellcheck source=../.env
. "$REPO_ROOT/.env"

# Host-side defaults (containers use internal hostnames)
RPC_URL="http://${CHAIN_HOST:-localhost}:${CHAIN_RPC_PORT}"
GATEWAY_URL="http://${GATEWAY_HOST:-localhost}:${GATEWAY_PORT}"
QUERY_COUNT="${1:-10}"
INDEXER="${RECEIVER_ADDRESS}"
REO_POLL_TIMEOUT=150  # Max wait: 2.5 cycles (worst case: just missed a cycle)
REO_POLL_INTERVAL=10  # Check every 10s

# -- Read REO contract address from config-local volume --
REO_ADDRESS=$(docker exec graph-node cat /opt/config/issuance.json 2>/dev/null \
  | jq -r '.["1337"].RewardsEligibilityOracle.address // empty' 2>/dev/null || true)
if [ -z "$REO_ADDRESS" ]; then
  echo "ERROR: RewardsEligibilityOracle address not found."
  echo "  Is the local network running? Is the REO contract deployed (Phase 4)?"
  echo "  Check: docker exec graph-node cat /opt/config/issuance.json | jq ."
  exit 1
fi

echo "=== REO Eligibility Cycle Test ==="
echo "  REO contract: $REO_ADDRESS"
echo "  Indexer:      $INDEXER"
echo "  RPC:          $RPC_URL"
echo "  Gateway:      $GATEWAY_URL"
echo "  Queries:      $QUERY_COUNT"
echo ""

# -- Helper functions --
check_eligible() {
  cast call --rpc-url="$RPC_URL" \
    "$REO_ADDRESS" "isEligible(address)(bool)" "$1" 2>/dev/null
}

get_validation_enabled() {
  cast call --rpc-url="$RPC_URL" \
    "$REO_ADDRESS" "getEligibilityValidation()(bool)" 2>/dev/null
}

get_last_oracle_update() {
  cast call --rpc-url="$RPC_URL" \
    "$REO_ADDRESS" "getLastOracleUpdateTime()(uint256)" 2>/dev/null
}

# ============================================================
# Step 1: Check contract state
# ============================================================
echo "--- Step 1: Check contract state ---"

validation=$(get_validation_enabled)
echo "  Eligibility validation enabled: $validation"

if [ "$validation" != "true" ]; then
  echo "  ERROR: Eligibility validation is not enabled on the REO contract."
  echo "  This should be enabled during deployment (Phase 4 in graph-contracts)."
  echo "  Re-run graph-contracts or enable manually:"
  echo "    cast send --rpc-url=$RPC_URL --private-key=\$ACCOUNT0_SECRET $REO_ADDRESS 'setEligibilityValidation(bool)' true"
  exit 1
fi

last_update=$(get_last_oracle_update)
echo "  Last oracle update time: $last_update"

# Seed lastOracleUpdateTime if it's 0 (prevents fail-safe from making everyone eligible).
# Call renewIndexerEligibility with an empty array — this sets the timestamp without
# marking any indexer eligible. Requires ORACLE_ROLE (ACCOUNT0).
if [ "$last_update" = "0" ]; then
  echo "  Seeding lastOracleUpdateTime (empty oracle update)..."
  cast send --rpc-url="$RPC_URL" --confirmations=0 \
    --private-key="$ACCOUNT0_SECRET" \
    "$REO_ADDRESS" "renewIndexerEligibility(address[],bytes)" "[]" "0x" > /dev/null
  echo "  Last oracle update time: $(get_last_oracle_update)"
fi

echo ""

# ============================================================
# Step 2: Verify indexer is NOT eligible
# ============================================================
echo "--- Step 2: Verify indexer is NOT eligible ---"

eligible_before=$(check_eligible "$INDEXER")
echo "  isEligible($INDEXER) = $eligible_before"

if [ "$eligible_before" = "true" ]; then
  echo ""
  echo "  WARNING: Indexer is already eligible. This can happen if:"
  echo "    - The REO node already submitted eligibility in a previous cycle"
  echo "    - The eligibility period hasn't expired yet"
  echo "  The test will continue but won't demonstrate the full deny→allow transition."
  echo ""
fi

# ============================================================
# Step 3: Send queries through the gateway
# ============================================================
echo "--- Step 3: Send $QUERY_COUNT queries through gateway ---"

# Mine blocks first to prevent "too far behind" errors
if ! "$SCRIPT_DIR/mine-block.sh" 5 > /dev/null 2>&1; then
  echo "  ERROR: Failed to mine blocks. Is the chain accessible at $RPC_URL?"
  exit 1
fi

success=0
fail=0
for i in $(seq 1 "$QUERY_COUNT"); do
  response=$(curl -s -w "\n%{http_code}" \
    "$GATEWAY_URL/api/subgraphs/id/$SUBGRAPH" \
    -H 'content-type: application/json' \
    -H "Authorization: Bearer $GATEWAY_API_KEY" \
    -d '{"query": "{ _meta { block { number } } }"}')
  http_code=$(echo "$response" | tail -1)
  if [ "$http_code" = "200" ]; then
    success=$((success + 1))
  else
    fail=$((fail + 1))
  fi
done

echo "  Sent $QUERY_COUNT queries: $success OK, $fail failed"

if [ "$success" -eq 0 ]; then
  echo "  ERROR: All queries failed. Is the gateway healthy?"
  echo "  Check: docker compose ps gateway"
  exit 1
fi

echo ""

# ============================================================
# Step 4: Poll until indexer is eligible (or timeout)
# ============================================================
echo "--- Step 4: Wait for REO node to process queries ---"
echo "  Polling every ${REO_POLL_INTERVAL}s, timeout ${REO_POLL_TIMEOUT}s"
echo "  (REO node cycles every 60s; may need up to 2 cycles if we just missed one)"
echo ""

elapsed=0
eligible_after="false"
while [ $elapsed -lt $REO_POLL_TIMEOUT ]; do
  sleep $REO_POLL_INTERVAL
  elapsed=$((elapsed + REO_POLL_INTERVAL))
  eligible_after=$(check_eligible "$INDEXER")
  if [ "$eligible_after" = "true" ]; then
    echo "  Eligible after ${elapsed}s"
    break
  fi
  printf "  %ds / %ds — not yet eligible...\r" "$elapsed" "$REO_POLL_TIMEOUT"
done

if [ "$eligible_after" != "true" ]; then
  echo "  Timed out after ${REO_POLL_TIMEOUT}s            "
fi

echo ""

# ============================================================
# Summary
# ============================================================
echo "=== Results ==="
echo "  Before queries: isEligible = $eligible_before"
echo "  After REO cycle: isEligible = $eligible_after"

if [ "$eligible_before" = "false" ] && [ "$eligible_after" = "true" ]; then
  echo ""
  echo "  SUCCESS: Full deny → allow cycle verified"
  echo "  The indexer was initially ineligible, served queries, and was marked eligible by the REO."
  exit 0
elif [ "$eligible_before" = "true" ] && [ "$eligible_after" = "true" ]; then
  echo ""
  echo "  PARTIAL: Indexer was already eligible before the test."
  echo "  The REO is working but the deny→allow transition was not demonstrated."
  echo "  To see the full cycle, wait for the eligibility period to expire or redeploy."
  exit 0
elif [ "$eligible_after" = "false" ]; then
  echo ""
  echo "  NEEDS MORE TIME: Indexer is still not eligible."
  echo "  The REO node may not have completed its cycle yet."
  echo "  Check REO logs: docker compose logs --tail 50 eligibility-oracle-node"
  echo "  Then re-check manually: cast call --rpc-url=$RPC_URL $REO_ADDRESS 'isEligible(address)(bool)' $INDEXER"
  exit 1
fi
