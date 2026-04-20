#!/bin/bash
# Debug script: replicate scenario 8 (accept + collect) in isolation.
# Monitors subgraph, agent logs, and on-chain state at each step.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$REPO_ROOT/.env"
[ -f "$REPO_ROOT/.env.local" ] && . "$REPO_ROOT/.env.local"

HARDHAT_RPC="http://${CHAIN_HOST:-localhost}:${CHAIN_RPC_PORT:-8545}"
NETWORK_SUBGRAPH_URL="http://${GRAPH_NODE_HOST:-localhost}:${GRAPH_NODE_GRAPHQL_PORT:-8000}/subgraphs/name/graph-network"
AGENT_URL="http://${INDEXER_AGENT_HOST:-localhost}:${INDEXER_MANAGEMENT_PORT:-7600}"
AGENT_CONTAINER="indexer-agent"
PG_HOST="${POSTGRES_HOST:-localhost}"
PG_PORT="${POSTGRES_PORT:-5432}"
PG_DB="indexer_components_1"
PG_USER="postgres"
PGCMD="psql -h $PG_HOST -p $PG_PORT -U $PG_USER -d $PG_DB -tAq"
export PATH="$HOME/.foundry/bin:$PATH"

SUBGRAPH_SERVICE_ADDRESS="${SUBGRAPH_SERVICE_ADDRESS:-$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/subgraph-service.json'))['1337']['SubgraphService']['address'])" 2>/dev/null)}"
RECURRING_COLLECTOR_ADDRESS="${RECURRING_COLLECTOR_ADDRESS:-$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['RecurringCollector']['address'])" 2>/dev/null)}"
GRT_TOKEN="${GRT_TOKEN:-$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['L2GraphToken']['address'])" 2>/dev/null)}"
PAYMENTS_ESCROW="${PAYMENTS_ESCROW:-$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['PaymentsEscrow']['address'])" 2>/dev/null)}"
EPOCH_MANAGER=$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['EpochManager']['address'])" 2>/dev/null)

# ── Helpers (copied from test-dips.sh) ─────────────────────────────

gql() {
  local url="$1"; local query="$2"
  curl -s --max-time 10 "$url" -H 'content-type: application/json' \
    -d "{\"query\": \"$query\"}" 2>/dev/null
}

ipfs_to_bytes32() {
  python3 -c "import base58; print('0x' + base58.b58decode('$1').hex()[4:])"
}

get_chain_timestamp() {
  cast block --rpc-url "$HARDHAT_RPC" latest --json 2>/dev/null \
    | python3 -c "import json,sys; print(int(json.load(sys.stdin)['timestamp'],16))"
}

get_chain_block() {
  curl -s "$HARDHAT_RPC" -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    | python3 -c "import json,sys; print(int(json.load(sys.stdin)['result'],16))"
}

get_subgraph_block() {
  curl -s "$NETWORK_SUBGRAPH_URL" -H 'content-type: application/json' \
    -d '{"query":"{_meta{block{number}}}"}' | jq -r '.data._meta.block.number'
}

wait_subgraph_at_chain_head() {
  local timeout="${1:-120}"
  local target=$(get_chain_block)
  local elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    local current=$(get_subgraph_block)
    if [ "$current" -ge "$target" ] 2>/dev/null; then return 0; fi
    sleep 2; elapsed=$((elapsed + 2))
  done
  return 1
}

encode_signed_rca() {
  local deployment_bytes32="$1"
  local deadline="${2:-$(( $(date +%s) + 7200 ))}"
  local ends_at="${3:-$(( $(date +%s) + 172800 ))}"
  local nonce="${4:-$(date +%s%N)}"

  local terms=$(cast abi-encode "f((uint256,uint256))" "(50,10)")
  local metadata=$(cast abi-encode "f((bytes32,uint8,bytes))" "($deployment_bytes32,0,$terms)")

  local domain_result
  domain_result=$(cast call --rpc-url "$HARDHAT_RPC" \
    "$RECURRING_COLLECTOR_ADDRESS" \
    "eip712Domain()(bytes1,string,string,uint256,address,bytes32,uint256[])" 2>/dev/null) || true

  local domain_name domain_version domain_chain_id domain_contract
  if [ -n "$domain_result" ]; then
    domain_name=$(echo "$domain_result" | sed -n '2p' | tr -d '"')
    domain_version=$(echo "$domain_result" | sed -n '3p' | tr -d '"')
    domain_chain_id=$(echo "$domain_result" | sed -n '4p')
    domain_contract=$(echo "$domain_result" | sed -n '5p')
  else
    domain_name="GraphTallyCollector"; domain_version="1"
    domain_chain_id=1337; domain_contract="$RECURRING_COLLECTOR_ADDRESS"
  fi

  local tmpfile=$(mktemp /tmp/rca-typed-data-XXXXXX.json)
  cat > "$tmpfile" <<EOFJSON
{
  "types": {
    "EIP712Domain": [
      {"name": "name", "type": "string"},
      {"name": "version", "type": "string"},
      {"name": "chainId", "type": "uint256"},
      {"name": "verifyingContract", "type": "address"}
    ],
    "RecurringCollectionAgreement": [
      {"name": "deadline", "type": "uint64"},
      {"name": "endsAt", "type": "uint64"},
      {"name": "payer", "type": "address"},
      {"name": "dataService", "type": "address"},
      {"name": "serviceProvider", "type": "address"},
      {"name": "maxInitialTokens", "type": "uint256"},
      {"name": "maxOngoingTokensPerSecond", "type": "uint256"},
      {"name": "minSecondsPerCollection", "type": "uint32"},
      {"name": "maxSecondsPerCollection", "type": "uint32"},
      {"name": "nonce", "type": "uint256"},
      {"name": "metadata", "type": "bytes"}
    ]
  },
  "primaryType": "RecurringCollectionAgreement",
  "domain": {
    "name": "$domain_name",
    "version": "$domain_version",
    "chainId": $domain_chain_id,
    "verifyingContract": "$domain_contract"
  },
  "message": {
    "deadline": $deadline,
    "endsAt": $ends_at,
    "payer": "$ACCOUNT0_ADDRESS",
    "dataService": "$SUBGRAPH_SERVICE_ADDRESS",
    "serviceProvider": "$RECEIVER_ADDRESS",
    "maxInitialTokens": "10000",
    "maxOngoingTokensPerSecond": "100",
    "minSecondsPerCollection": 3600,
    "maxSecondsPerCollection": 7200,
    "nonce": "$nonce",
    "metadata": "$metadata"
  }
}
EOFJSON

  local signature=$(cast wallet sign --data --from-file --private-key "$ACCOUNT0_SECRET" "$tmpfile")
  rm -f "$tmpfile"

  cast abi-encode \
    "f(((uint64,uint64,address,address,address,uint256,uint256,uint32,uint32,uint256,bytes),bytes))" \
    "(($deadline,$ends_at,${ACCOUNT0_ADDRESS},${SUBGRAPH_SERVICE_ADDRESS},${RECEIVER_ADDRESS},10000,100,3600,7200,$nonce,$metadata),$signature)"
}

ensure_payer_escrow() {
  local amount="1000000000000000000000"
  local balance=$(cast call --rpc-url "$HARDHAT_RPC" \
    "$PAYMENTS_ESCROW" "getBalance(address,address,address)(uint256)" \
    "$ACCOUNT0_ADDRESS" "$RECURRING_COLLECTOR_ADDRESS" "$RECEIVER_ADDRESS" 2>/dev/null || echo "0")
  if [ "$balance" != "0" ] && [ -n "$balance" ]; then
    echo "  OK    Payer escrow already funded ($balance)"; return 0
  fi
  echo "  ...   Funding payer escrow..."
  cast send --rpc-url "$HARDHAT_RPC" --private-key "$ACCOUNT0_SECRET" \
    "$GRT_TOKEN" "approve(address,uint256)" "$PAYMENTS_ESCROW" "$amount" \
    --confirmations 1 > /dev/null 2>&1
  cast send --rpc-url "$HARDHAT_RPC" --private-key "$ACCOUNT0_SECRET" \
    "$PAYMENTS_ESCROW" "deposit(address,address,uint256)" "$RECURRING_COLLECTOR_ADDRESS" "$RECEIVER_ADDRESS" "$amount" \
    --confirmations 1 > /dev/null 2>&1
  echo "  OK    Payer escrow funded"
}

ensure_signer_authorized() {
  local is_auth=$(cast call --rpc-url "$HARDHAT_RPC" \
    "$RECURRING_COLLECTOR_ADDRESS" "isAuthorized(address,address)(bool)" \
    "$ACCOUNT0_ADDRESS" "$ACCOUNT0_ADDRESS" 2>/dev/null || echo "false")
  if [ "$is_auth" = "true" ]; then
    echo "  OK    Signer already authorized"; return 0
  fi
  echo "  ...   Authorizing signer..."
  local chain_id=$(cast chain-id --rpc-url "$HARDHAT_RPC")
  local deadline=$(( $(date +%s) + 86400 ))
  local packed=$(cast abi-encode --packed \
    "f(uint256,address,string,uint256,address)" \
    "$chain_id" "$RECURRING_COLLECTOR_ADDRESS" "authorizeSignerProof" "$deadline" "$ACCOUNT0_ADDRESS")
  local hash=$(cast keccak "$packed")
  local proof=$(cast wallet sign --private-key "$ACCOUNT0_SECRET" "$hash")
  cast send --rpc-url "$HARDHAT_RPC" --private-key "$ACCOUNT0_SECRET" \
    "$RECURRING_COLLECTOR_ADDRESS" "authorizeSigner(address,uint256,bytes)" \
    "$ACCOUNT0_ADDRESS" "$deadline" "$proof" \
    --confirmations 1 > /dev/null 2>&1
  echo "  OK    Signer authorized"
}

ensure_clean_allocation() {
  local deployment_ipfs="$1"
  local alloc_id=$(curl -s --max-time 10 "$NETWORK_SUBGRAPH_URL" \
    -H 'content-type: application/json' \
    -d "{\"query\": \"{ allocations(where: { subgraphDeployment_: { ipfsHash: \\\"$deployment_ipfs\\\" }, status: Active }) { id } }\"}" \
    | jq -r '.data.allocations[0].id // empty')

  if [ -z "$alloc_id" ]; then
    echo "  WARN  No active allocation found"; return 1
  fi

  # Check for existing agreement
  local has_agreement=$(curl -s --max-time 10 "$NETWORK_SUBGRAPH_URL" \
    -H 'content-type: application/json' \
    -d "{\"query\": \"{ indexingAgreements(where: { allocationId: \\\"$alloc_id\\\", state_in: [1, 3] }) { id } }\"}" \
    | jq -r '.data.indexingAgreements[0].id // empty')

  if [ -n "$has_agreement" ]; then
    echo "  ...   Allocation $alloc_id has agreement $has_agreement, closing..."
    cast send --rpc-url "$HARDHAT_RPC" --private-key "$RECEIVER_SECRET" \
      "$SUBGRAPH_SERVICE_ADDRESS" "stopService(address,bytes)" \
      "$RECEIVER_ADDRESS" "$(cast abi-encode 'f(address)' "$alloc_id")" \
      --confirmations 1 > /dev/null 2>&1
    local elapsed=0
    while [ "$elapsed" -lt 180 ]; do
      sleep 5; elapsed=$((elapsed + 5))
      local new_alloc=$(curl -s --max-time 10 "$NETWORK_SUBGRAPH_URL" \
        -H 'content-type: application/json' \
        -d "{\"query\": \"{ allocations(where: { subgraphDeployment_: { ipfsHash: \\\"$deployment_ipfs\\\" }, status: Active }) { id } }\"}" \
        | jq -r '.data.allocations[0].id // empty')
      if [ -n "$new_alloc" ] && [ "$new_alloc" != "$alloc_id" ]; then
        echo "  OK    Fresh allocation: $new_alloc"; return 0
      fi
    done
    echo "  WARN  Timed out waiting for fresh allocation"; return 1
  fi

  echo "  OK    Allocation $alloc_id is clean (no active agreement)"
  return 0
}

get_agreement_id() {
  cast call --rpc-url "$HARDHAT_RPC" \
    "$RECURRING_COLLECTOR_ADDRESS" \
    "generateAgreementId(address,address,address,uint64,uint256)(bytes16)" \
    "$1" "$2" "$3" "$4" "$5"
}

get_last_collection_at() {
  local result=$(cast call --rpc-url "$HARDHAT_RPC" \
    "$RECURRING_COLLECTOR_ADDRESS" \
    "getAgreement(bytes16)(address,address,address,uint64,uint64,uint64,uint256,uint256,uint32,uint32,uint32,uint64,uint8)" \
    "$1")
  echo "$result" | sed -n '5p'
}

# ── Main ─────────────────────────────────────────────────────────────

echo "=== Debug: Scenario 8 (accept + collect) ==="
echo ""

EPOCH_LEN=$(cast call --rpc-url "$HARDHAT_RPC" "$EPOCH_MANAGER" "epochLength()(uint256)")
EPOCH=$(cast call --rpc-url "$HARDHAT_RPC" "$EPOCH_MANAGER" "currentEpoch()(uint256)")
echo "  Epoch: $EPOCH, epoch length: $EPOCH_LEN blocks"
echo ""

# --- Step 1: Setup ---
echo "=== Step 1: Setup ==="
ensure_payer_escrow
ensure_signer_authorized

DEPLOYMENT_IPFS=$(gql "$AGENT_URL" \
  "{ indexingRules(merged: false) { identifier identifierType decisionBasis } }" \
  | jq -r '.data.indexingRules[] | select(.identifierType == "deployment" and .decisionBasis == "always") | .identifier' \
  | head -1)

if [ -z "$DEPLOYMENT_IPFS" ] || [ "$DEPLOYMENT_IPFS" = "null" ]; then
  echo "  FATAL: No existing deployment with 'always' rule"; exit 1
fi
echo "  Deployment: $DEPLOYMENT_IPFS"

DEPLOYMENT_BYTES32=$(ipfs_to_bytes32 "$DEPLOYMENT_IPFS")
ensure_clean_allocation "$DEPLOYMENT_IPFS" || { echo "  FATAL: No clean allocation"; exit 1; }
echo ""

# --- Step 2: Insert proposal ---
echo "=== Step 2: Insert signed proposal ==="
UUID="d0b00008-0008-0008-0008-000000000008"
$PGCMD -c "DELETE FROM pending_rca_proposals WHERE id = '$UUID';" || true

TS=$(get_chain_timestamp)
DEADLINE=$(( TS + 7200 ))
ENDS_AT=$(( TS + 172800 ))
NONCE=$(date +%s%N)
PAYLOAD=$(encode_signed_rca "$DEPLOYMENT_BYTES32" "$DEADLINE" "$ENDS_AT" "$NONCE")

if [ -z "$PAYLOAD" ]; then
  echo "  FATAL: Failed to encode signed RCA"; exit 1
fi

AGREEMENT_ID=$(get_agreement_id "$ACCOUNT0_ADDRESS" "$SUBGRAPH_SERVICE_ADDRESS" "$RECEIVER_ADDRESS" "$DEADLINE" "$NONCE")
echo "  Agreement ID: $AGREEMENT_ID"

PAYLOAD_PG="\\\\x${PAYLOAD#0x}"
$PGCMD -c "INSERT INTO pending_rca_proposals (id, signed_payload, version, status, created_at, updated_at)
  VALUES ('$UUID', E'$PAYLOAD_PG', 2, 'pending', NOW(), NOW());"
echo "  Proposal inserted"
echo ""

# --- Step 3: Wait for acceptance ---
echo "=== Step 3: Wait for agent to accept (180s max) ==="
ELAPSED=0
while [ "$ELAPSED" -lt 180 ]; do
  STATUS=$($PGCMD -c "SELECT status FROM pending_rca_proposals WHERE id = '$UUID';")
  if [ "$STATUS" = "accepted" ]; then
    echo "  PASS  Proposal accepted after ${ELAPSED}s"
    break
  elif [ "$STATUS" = "rejected" ]; then
    echo "  FAIL  Proposal rejected after ${ELAPSED}s"
    docker logs "$AGENT_CONTAINER" 2>&1 | grep -i "reject\|error.*$UUID\|error.*$AGREEMENT_ID" | tail -5
    exit 1
  fi
  sleep 5; ELAPSED=$((ELAPSED + 5))
  [ $((ELAPSED % 30)) -eq 0 ] && echo "  ...   ${ELAPSED}s: status=$STATUS"
done
if [ "$STATUS" != "accepted" ]; then
  echo "  FAIL  Timed out (status=$STATUS)"; exit 1
fi
echo ""

# Check agreement in subgraph
echo "=== Agreement state after acceptance ==="
curl -s "$NETWORK_SUBGRAPH_URL" -H 'content-type: application/json' \
  -d "{\"query\":\"{ indexingAgreements(where: { id: \\\"$AGREEMENT_ID\\\" }) { id state lastCollectionAt allocationId } }\"}" | jq '.data'

INITIAL_LAST_COLLECTED=$(get_last_collection_at "$AGREEMENT_ID")
echo "  On-chain lastCollectionAt: $INITIAL_LAST_COLLECTED"
echo ""

# --- Step 4: Advance time ---
echo "=== Step 4: Advance time (100 blocks × 37s = 3700s, ~2 epochs) ==="
AGENT_LOG_MARKER=$(docker logs "$AGENT_CONTAINER" 2>&1 | wc -l)

EPOCH_BEFORE=$(cast call --rpc-url "$HARDHAT_RPC" "$EPOCH_MANAGER" "currentEpoch()(uint256)")
cast rpc --rpc-url="$HARDHAT_RPC" anvil_mine 100 37 > /dev/null
EPOCH_AFTER=$(cast call --rpc-url "$HARDHAT_RPC" "$EPOCH_MANAGER" "currentEpoch()(uint256)")
echo "  Epoch: $EPOCH_BEFORE → $EPOCH_AFTER (jumped $((EPOCH_AFTER - EPOCH_BEFORE)))"

echo "  Waiting for subgraph sync..."
wait_subgraph_at_chain_head 60 && echo "  Subgraph synced" || echo "  WARN  Subgraph sync timed out"
echo ""

# --- Step 5: Check state after time advance ---
echo "=== Step 5: State after time advance ==="
echo "  Agreement in subgraph:"
curl -s "$NETWORK_SUBGRAPH_URL" -H 'content-type: application/json' \
  -d "{\"query\":\"{ indexingAgreements(where: { id: \\\"$AGREEMENT_ID\\\" }) { id state lastCollectionAt } }\"}" | jq '.data'

echo "  All agreements (state_in [1,3]) for indexer:"
curl -s "$NETWORK_SUBGRAPH_URL" -H 'content-type: application/json' \
  -d "{\"query\":\"{ indexingAgreements(where: { serviceProvider: \\\"$(echo $RECEIVER_ADDRESS | tr '[:upper:]' '[:lower:]')\\\", state_in: [1, 3] }) { id state lastCollectionAt } }\"}" | jq '.data'

echo "  Allocation status:"
curl -s "$NETWORK_SUBGRAPH_URL" -H 'content-type: application/json' \
  -d "{\"query\":\"{ allocations(where: { subgraphDeployment_: { ipfsHash: \\\"$DEPLOYMENT_IPFS\\\" }, status: Active }) { id createdAtEpoch } }\"}" | jq '.data'
echo ""

# --- Step 6: Wait for collection ---
echo "=== Step 6: Wait for agent to collect (120s max) ==="
ELAPSED=0
while [ "$ELAPSED" -lt 120 ]; do
  CURRENT=$(get_last_collection_at "$AGREEMENT_ID")
  if [ "$CURRENT" != "$INITIAL_LAST_COLLECTED" ] && [ -n "$CURRENT" ]; then
    echo "  PASS  Collection happened after ${ELAPSED}s (lastCollectionAt: $INITIAL_LAST_COLLECTED → $CURRENT)"
    break
  fi
  sleep 5; ELAPSED=$((ELAPSED + 5))
  [ $((ELAPSED % 20)) -eq 0 ] && echo "  ...   ${ELAPSED}s: lastCollectionAt=$CURRENT (waiting for change from $INITIAL_LAST_COLLECTED)"
done
if [ "$CURRENT" = "$INITIAL_LAST_COLLECTED" ]; then
  echo "  FAIL  No collection after 120s"
fi
echo ""

# --- Agent logs ---
echo "=== Agent logs: collection-related (since time advance) ==="
docker logs "$AGENT_CONTAINER" 2>&1 | tail -n +"$AGENT_LOG_MARKER" \
  | grep -iE "collectAgreement|No collectable|ready for collection|tryCollect|blockHash|getCollectionInfo|not collectable|Deterministic|Transient|entityCount|subgraphFeatures" \
  | grep -v "FreshnessChecker" \
  | tail -20
echo ""

echo "=== Agent logs: allocation lifecycle (since time advance) ==="
docker logs "$AGENT_CONTAINER" 2>&1 | tail -n +"$AGENT_LOG_MARKER" \
  | grep -iE "expir|staleness|presentPOI|stopService|unallocate|cancelIndex|DIPS agreement" \
  | tail -10
echo ""

echo "=== Agent logs: errors (since time advance) ==="
docker logs "$AGENT_CONTAINER" 2>&1 | tail -n +"$AGENT_LOG_MARKER" \
  | grep -E '"level":4[0-9]|"level":50' \
  | grep -v "deprecated\|No recently closed\|Recently executed\|Action not queued\|recentlyAttempted" \
  | tail -10

# Cleanup
$PGCMD -c "DELETE FROM pending_rca_proposals WHERE id = '$UUID';" || true
