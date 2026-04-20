#!/bin/bash
# Debug script to investigate allocation close + recreation behavior
# Tests the flow: close allocation with agreement -> agent recreates allocation

set -euo pipefail

HARDHAT_RPC="http://localhost:8545"
AGENT_URL="http://localhost:7600"
INDEXER_CLI="node ${INDEXER_AGENT_SOURCE_ROOT:-../indexer}/packages/indexer-cli/bin/graph-indexer"

# Ensure CLI is connected
$INDEXER_CLI indexer connect "$AGENT_URL" > /dev/null 2>&1

gql() {
  local url="$1" query="$2"
  curl -sf "$url" -H 'content-type: application/json' -d "{\"query\":\"$query\"}"
}

echo "=== Debug: Close Allocation with Agreement ==="
echo ""

# Step 1: Current state
echo "--- Step 1: Current State ---"
echo ""
echo "Epoch state:"
EPOCH_MANAGER=$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['EpochManager']['address'])")
echo "  EpochManager: $EPOCH_MANAGER"
echo "  Current epoch: $(cast call --rpc-url $HARDHAT_RPC $EPOCH_MANAGER 'currentEpoch()(uint256)')"
echo "  Epoch length: $(cast call --rpc-url $HARDHAT_RPC $EPOCH_MANAGER 'epochLength()(uint256)')"
echo "  Current epoch block: $(cast call --rpc-url $HARDHAT_RPC $EPOCH_MANAGER 'currentEpochBlock()(uint256)')"
echo "  Current block: $(cast bn --rpc-url $HARDHAT_RPC)"
echo ""

echo "EBO subgraph state:"
ebo=$(gql "http://localhost:8000/subgraphs/name/block-oracle" \
  "{ networks(first:5) { id latestValidBlockNumber { epochNumber blockNumber } } _meta { block { number } } }")
echo "  $ebo" | python3 -m json.tool
echo ""

echo "Active allocations:"
$INDEXER_CLI indexer allocations get --network hardhat 2>&1
echo ""

echo "Indexing rules:"
$INDEXER_CLI indexer rules get --network hardhat 2>&1
echo ""

# Find allocation for QmTE7w (the test deployment)
DEPLOYMENT="QmTE7w2WpB8TokzZBTSAEf7NpTsWPwvELr45r81RvqSbuW"
echo "Looking for active allocation for $DEPLOYMENT..."
alloc_result=$(gql "http://localhost:8000/subgraphs/name/graph-network" \
  "{ allocations(where: { subgraphDeployment_: { ipfsHash: \\\"$DEPLOYMENT\\\" }, status: Active }) { id } }")
alloc_id=$(echo "$alloc_result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data']['allocations'][0]['id'] if d['data']['allocations'] else 'NONE')")
echo "  Allocation: $alloc_id"

if [ "$alloc_id" = "NONE" ]; then
  echo "  No active allocation found. Cannot proceed."
  exit 1
fi

# Check for agreement on this allocation
agreement_result=$(gql "http://localhost:8000/subgraphs/name/graph-network" \
  "{ indexingAgreements(where: { allocationId: \\\"$alloc_id\\\", state_in: [1, 3] }) { id state } }")
has_agreement=$(echo "$agreement_result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data']['indexingAgreements'][0]['id'] if d['data']['indexingAgreements'] else 'NONE')")
echo "  Agreement on allocation: $has_agreement"
echo ""

# Step 2: Capture agent logs before close, then try to close
echo "--- Step 2: Attempting CLI Close with --force ---"
echo ""

# Get current agent log position
log_marker=$(docker logs indexer-agent 2>&1 | wc -l)

echo "Closing allocation $alloc_id with --force..."
close_output=$($INDEXER_CLI indexer allocations close "$alloc_id" --force --network hardhat 2>&1) || true
echo "CLI output:"
echo "$close_output"
echo ""

# Wait a moment for agent to process
sleep 5

echo "Agent logs since close attempt:"
docker logs indexer-agent 2>&1 | tail -n +$((log_marker + 1)) | grep -v "^$" | head -40
echo ""

# Step 3: Check state after close
echo "--- Step 3: State After Close ---"
echo ""

echo "Active allocations:"
$INDEXER_CLI indexer allocations get --network hardhat 2>&1
echo ""

echo "Indexing rules (check if rule changed to OFFCHAIN):"
$INDEXER_CLI indexer rules get --network hardhat 2>&1
echo ""

# Step 4: If close succeeded, monitor for re-creation
if echo "$close_output" | grep -qi "error\|fail"; then
  echo "Close FAILED. Checking if we can mine blocks to help..."
  echo ""

  # Mine a block to make chain/subgraph advance
  echo "Mining 1 block..."
  cast rpc --rpc-url="$HARDHAT_RPC" evm_mine > /dev/null
  sleep 3

  echo "Retrying close..."
  $INDEXER_CLI indexer allocations close "$alloc_id" --force --network hardhat 2>&1 || true
else
  echo "Close appeared to succeed."
  echo ""
  echo "Checking if rule was changed to OFFCHAIN (this prevents re-creation)..."
  rule_check=$($INDEXER_CLI indexer rules get --network hardhat 2>&1)
  if echo "$rule_check" | grep -q "offchain"; then
    echo "  YES - rule was changed to OFFCHAIN. Agent will NOT recreate allocation."
    echo "  This is by design: closeAllocation sets rule to OFFCHAIN."
    echo ""
    echo "  Restoring rule to 'always'..."
    $INDEXER_CLI indexer rules set "$DEPLOYMENT" decisionBasis always --network hardhat 2>&1
    echo ""

    echo "  Waiting for agent reconciliation loop (up to 60s)..."
    for i in $(seq 1 12); do
      sleep 5
      new_alloc=$(gql "http://localhost:8000/subgraphs/name/graph-network" \
        "{ allocations(where: { subgraphDeployment_: { ipfsHash: \\\"$DEPLOYMENT\\\" }, status: Active }) { id } }" | \
        python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data']['allocations'][0]['id'] if d['data']['allocations'] else 'NONE')")
      if [ "$new_alloc" != "NONE" ] && [ "$new_alloc" != "$alloc_id" ]; then
        echo "  New allocation created: $new_alloc"
        break
      fi
      echo "  ($((i * 5))s) Still waiting... current: $new_alloc"
    done
  fi
fi

echo ""
echo "=== Debug Complete ==="
