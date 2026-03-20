#!/bin/bash
# DIPs integration tests for indexer-agent.
#
# Tests that the indexer-agent correctly reads pending RCA proposals from
# the pending_rca_proposals table and creates/skips indexing rules.
#
# Prerequisites:
#   - Local network running with DIPs profile (compose/dev/dips.yaml)
#   - indexer-agent healthy and connected
#   - pending_rca_proposals table exists (migration 23)
#
# Usage: ./scripts/test-dips.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../.env
. "$REPO_ROOT/.env"
[ -f "$REPO_ROOT/.env.local" ] && . "$REPO_ROOT/.env.local"

AGENT_URL="http://${INDEXER_AGENT_HOST:-localhost}:${INDEXER_MANAGEMENT_PORT:-7600}"
PG_HOST="${POSTGRES_HOST:-localhost}"
PG_PORT="${POSTGRES_PORT:-5432}"
PG_DB="indexer_components_1"
PG_USER="postgres"
PGCMD="psql -h $PG_HOST -p $PG_PORT -U $PG_USER -d $PG_DB -tAq"

export PATH="$HOME/.foundry/bin:$PATH"

pass=0
fail=0
total=0

# ── Helpers ───────────────────────────────────────────────────────────

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

# Convert bytes32 (0x-prefixed, 64 hex chars) to IPFS CIDv0 (Qm...).
# Prepends the multihash prefix 0x1220 and base58-encodes.
bytes32_to_ipfs() {
  local hex="${1#0x}"
  python3 -c "import base58; print(base58.b58encode(bytes.fromhex('1220${hex}')).decode())"
}

# Convert IPFS CIDv0 (Qm...) to bytes32 (0x-prefixed, 64 hex chars).
# Strips the multihash prefix 0x1220.
ipfs_to_bytes32() {
  python3 -c "import base58; print('0x' + base58.b58decode('$1').hex()[4:])"
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

# Encode a valid SignedRCA payload using cast abi-encode.
# Args: $1 = deployment bytes32 (0x-prefixed, 32 bytes)
# Uses hardcoded test values for other fields.
# Outputs: hex-encoded payload (0x-prefixed)
encode_rca() {
  local deployment_bytes32="$1"

  local terms
  terms=$(cast abi-encode \
    "f((uint256,uint256))" \
    "(1000,50)")

  local metadata
  metadata=$(cast abi-encode \
    "f((bytes32,uint8,bytes))" \
    "($deployment_bytes32,1,$terms)")

  local signed_rca
  signed_rca=$(cast abi-encode \
    "f(((uint64,uint64,address,address,address,uint256,uint256,uint32,uint32,uint256,bytes),bytes))" \
    "((1900000000,2000000000,${ACCOUNT0_ADDRESS},${RECEIVER_ADDRESS},${RECEIVER_ADDRESS},10000,100,3600,86400,42,$metadata),0xaabbccdd)")

  echo "$signed_rca"
}

# Insert a proposal row into pending_rca_proposals.
# Args: $1 = uuid, $2 = hex payload (0x-prefixed)
insert_proposal() {
  local uuid="$1"
  local payload_hex="$2"
  # Strip 0x prefix for postgres bytea hex format
  local payload_pg="\\\\x${payload_hex#0x}"

  $PGCMD -c "INSERT INTO pending_rca_proposals (id, signed_payload, version, status, created_at, updated_at)
    VALUES ('$uuid', E'$payload_pg', 2, 'pending', NOW(), NOW());"
}

# Poll management API for a DIPS indexing rule matching a deployment.
# Args: $1 = deployment IPFS hash, $2 = timeout in seconds
# Returns: 0 if found, 1 if timeout
poll_dips_rule() {
  local deployment_hash="$1"
  local timeout="${2:-120}"
  local elapsed=0
  local interval=5

  while [ "$elapsed" -lt "$timeout" ]; do
    local rules
    rules=$(gql "$AGENT_URL" \
      "{ indexingRules(merged: false) { identifier decisionBasis } }")

    if echo "$rules" | jq -e \
      ".data.indexingRules[] | select(.identifier == \"$deployment_hash\" and .decisionBasis == \"dips\")" \
      > /dev/null 2>&1; then
      return 0
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  return 1
}

# Check a proposal's status in the database.
# Args: $1 = uuid, $2 = expected status
check_proposal_status() {
  local uuid="$1"
  local expected="$2"
  local actual
  actual=$($PGCMD -c "SELECT status FROM pending_rca_proposals WHERE id = '$uuid';")
  [ "$actual" = "$expected" ]
}

# Count DIPS rules for a given deployment.
# Args: $1 = deployment IPFS hash
count_dips_rules() {
  local deployment_hash="$1"
  local rules
  rules=$(gql "$AGENT_URL" \
    "{ indexingRules(merged: false) { identifier decisionBasis } }")
  echo "$rules" | jq \
    "[.data.indexingRules[] | select(.identifier == \"$deployment_hash\" and .decisionBasis == \"dips\")] | length"
}

# Clean up: delete a proposal from the database and remove its DIPS rule.
# Args: $1 = uuid, $2 = deployment IPFS hash (optional)
cleanup_proposal() {
  local uuid="$1"
  local deployment_hash="${2:-}"

  $PGCMD -c "DELETE FROM pending_rca_proposals WHERE id = '$uuid';" || true

  if [ -n "$deployment_hash" ]; then
    gql "$AGENT_URL" "mutation { deleteIndexingRule(identifier: { identifier: \\\"$deployment_hash\\\", protocolNetwork: \\\"hardhat\\\" }) }" > /dev/null 2>&1 || true
  fi
}

# ── On-chain helpers (PLAN_03 scenarios) ──────────────────────────────

HARDHAT_RPC="http://${CHAIN_HOST:-localhost}:${CHAIN_RPC_PORT:-8545}"
NETWORK_SUBGRAPH_URL="http://${GRAPH_NODE_HOST:-localhost}:${GRAPH_NODE_GRAPHQL_PORT:-8000}/subgraphs/name/graph-network"

# Read contract addresses from the agent's config (docker volume) to avoid stale hardcoded values.
# These are regenerated on each local-network deploy, so hardcoding them breaks.
SUBGRAPH_SERVICE_ADDRESS="${SUBGRAPH_SERVICE_ADDRESS:-$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/subgraph-service.json'))['1337']['SubgraphService']['address'])" 2>/dev/null)}"
COLLECTOR_ADDRESS="${COLLECTOR_ADDRESS:-$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['GraphTallyCollector']['address'])" 2>/dev/null)}"
RECURRING_COLLECTOR_ADDRESS="${RECURRING_COLLECTOR_ADDRESS:-$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['RecurringCollector']['address'])" 2>/dev/null)}"
GRT_TOKEN="${GRT_TOKEN:-$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['L2GraphToken']['address'])" 2>/dev/null)}"
PAYMENTS_ESCROW="${PAYMENTS_ESCROW:-$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['PaymentsEscrow']['address'])" 2>/dev/null)}"

# Encode a PROPERLY SIGNED RCA payload using cast EIP-712 signing.
# Args: $1 = deployment bytes32, $2 = deadline (optional), $3 = endsAt (optional)
# Outputs: hex-encoded signed payload (0x-prefixed)
encode_signed_rca() {
  local deployment_bytes32="$1"
  local deadline="${2:-$(( $(date +%s) + 7200 ))}"
  local ends_at="${3:-$(( $(date +%s) + 172800 ))}"
  local nonce="${4:-$(date +%s%N)}"  # caller can pass nonce, or auto-generate

  # 1. ABI-encode metadata (same pattern as encode_rca)
  local terms
  terms=$(cast abi-encode "f((uint256,uint256))" "(50,10)")
  local metadata
  metadata=$(cast abi-encode "f((bytes32,uint8,bytes))" "($deployment_bytes32,0,$terms)")

  # 2. Query EIP-712 domain from the collector contract (EIP-5267)
  local domain_result
  domain_result=$(cast call --rpc-url "$HARDHAT_RPC" \
    "$RECURRING_COLLECTOR_ADDRESS" \
    "eip712Domain()(bytes1,string,string,uint256,address,bytes32,uint256[])" 2>/dev/null) || true

  local domain_name domain_version domain_chain_id domain_contract
  if [ -n "$domain_result" ]; then
    # Strip surrounding quotes from cast call string output
    domain_name=$(echo "$domain_result" | sed -n '2p' | tr -d '"')
    domain_version=$(echo "$domain_result" | sed -n '3p' | tr -d '"')
    domain_chain_id=$(echo "$domain_result" | sed -n '4p')
    domain_contract=$(echo "$domain_result" | sed -n '5p')
  else
    domain_name="GraphTallyCollector"
    domain_version="1"
    domain_chain_id=1337
    domain_contract="$RECURRING_COLLECTOR_ADDRESS"
  fi

  # 3. Build EIP-712 typed data JSON
  local tmpfile
  tmpfile=$(mktemp /tmp/rca-typed-data-XXXXXX.json)
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

  # 4. Sign the typed data
  local signature
  signature=$(cast wallet sign --data --from-file --private-key "$ACCOUNT0_SECRET" "$tmpfile")
  rm -f "$tmpfile"

  # 5. ABI-encode the full SignedRCA tuple
  cast abi-encode \
    "f(((uint64,uint64,address,address,address,uint256,uint256,uint32,uint32,uint256,bytes),bytes))" \
    "(($deadline,$ends_at,${ACCOUNT0_ADDRESS},${SUBGRAPH_SERVICE_ADDRESS},${RECEIVER_ADDRESS},10000,100,3600,86400,$nonce,$metadata),$signature)"
}

# Poll for a proposal's status to change.
# Args: $1 = uuid, $2 = expected status, $3 = timeout in seconds
# Returns: 0 if status matches, 1 if timeout
poll_proposal_status() {
  local uuid="$1"
  local expected="$2"
  local timeout="${3:-180}"
  local elapsed=0
  local interval=5

  while [ "$elapsed" -lt "$timeout" ]; do
    if check_proposal_status "$uuid" "$expected"; then
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  return 1
}

# Check if an allocation exists for a deployment via the network subgraph.
# Args: $1 = deployment IPFS hash
# Returns: 0 if active allocation found, 1 if not
check_allocation_exists() {
  local deployment_hash="$1"
  local result
  result=$(curl -s --max-time 10 "$NETWORK_SUBGRAPH_URL" \
    -H 'content-type: application/json' \
    -d "{\"query\": \"{ allocations(where: { subgraphDeployment_: { ipfsHash: \\\"$deployment_hash\\\" }, status: Active }) { id } }\"}")
  echo "$result" | jq -e '.data.allocations | length > 0' > /dev/null 2>&1
}

# Ensure the payer (ACCOUNT0) has tokens deposited in PaymentsEscrow for the indexer.
# Idempotent: checks balance first, deposits only if needed.
ensure_payer_escrow() {
  local amount="1000000000000000000000" # 1000 GRT (18 decimals)

  local balance
  balance=$(cast call --rpc-url "$HARDHAT_RPC" \
    "$PAYMENTS_ESCROW" "getBalance(address,address,address)(uint256)" \
    "$ACCOUNT0_ADDRESS" "$RECEIVER_ADDRESS" "$RECURRING_COLLECTOR_ADDRESS" 2>/dev/null || echo "0")

  if [ "$balance" != "0" ] && [ -n "$balance" ]; then
    echo "  OK    Payer escrow already funded ($balance)"
    return 0
  fi

  echo "  ...   Funding payer escrow (approve + deposit)..."
  cast send --rpc-url "$HARDHAT_RPC" --private-key "$ACCOUNT0_SECRET" \
    "$GRT_TOKEN" "approve(address,uint256)" "$PAYMENTS_ESCROW" "$amount" \
    --confirmations 1 > /dev/null 2>&1
  cast send --rpc-url "$HARDHAT_RPC" --private-key "$ACCOUNT0_SECRET" \
    "$PAYMENTS_ESCROW" "deposit(address,address,uint256)" "$RECEIVER_ADDRESS" "$RECURRING_COLLECTOR_ADDRESS" "$amount" \
    --confirmations 1 > /dev/null 2>&1
  echo "  OK    Payer escrow funded"
}

# Ensure the payer (ACCOUNT0) has authorized itself as a signer on the RecurringCollector.
# Required for EIP-712 signed RCA acceptance. Idempotent.
ensure_signer_authorized() {
  local is_auth
  is_auth=$(cast call --rpc-url "$HARDHAT_RPC" \
    "$RECURRING_COLLECTOR_ADDRESS" "isAuthorized(address,address)(bool)" \
    "$ACCOUNT0_ADDRESS" "$ACCOUNT0_ADDRESS" 2>/dev/null || echo "false")

  if [ "$is_auth" = "true" ]; then
    echo "  OK    Signer already authorized on RecurringCollector"
    return 0
  fi

  echo "  ...   Authorizing signer on RecurringCollector..."

  local chain_id
  chain_id=$(cast chain-id --rpc-url "$HARDHAT_RPC")

  local deadline=$(( $(date +%s) + 86400 ))

  # Replicate ethers.solidityPacked(['uint256','address','string','uint256','address'], [...])
  local packed
  packed=$(cast abi-encode --packed \
    "f(uint256,address,string,uint256,address)" \
    "$chain_id" "$RECURRING_COLLECTOR_ADDRESS" "authorizeSignerProof" "$deadline" "$ACCOUNT0_ADDRESS")

  local hash
  hash=$(cast keccak "$packed")

  # Replicate wallet.signMessage(getBytes(hash)) — cast wallet sign applies Ethereum prefix by default
  local proof
  proof=$(cast wallet sign --private-key "$ACCOUNT0_SECRET" "$hash")

  cast send --rpc-url "$HARDHAT_RPC" --private-key "$ACCOUNT0_SECRET" \
    "$RECURRING_COLLECTOR_ADDRESS" "authorizeSigner(address,uint256,bytes)" \
    "$ACCOUNT0_ADDRESS" "$deadline" "$proof" \
    --confirmations 1 > /dev/null 2>&1
  echo "  OK    Signer authorized on RecurringCollector"
}

# ── Subgraph deny/undeny helpers (PLAN_03A scenarios) ─────────────────

REWARDS_MANAGER_ADDRESS="${REWARDS_MANAGER_ADDRESS:-$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['RewardsManager']['address'])" 2>/dev/null)}"

# Ensure ORACLE_ADDRESS is registered as the subgraphAvailabilityOracle.
# Called once; idempotent — skips if already set.
ensure_subgraph_availability_oracle() {
  local current_oracle
  current_oracle=$(cast call --rpc-url "$HARDHAT_RPC" \
    "$REWARDS_MANAGER_ADDRESS" "subgraphAvailabilityOracle()(address)")
  current_oracle=$(echo "$current_oracle" | tr '[:upper:]' '[:lower:]')
  local target
  target=$(echo "$ORACLE_ADDRESS" | tr '[:upper:]' '[:lower:]')

  if [ "$current_oracle" = "$target" ]; then
    echo "  OK    Subgraph availability oracle already set to $ORACLE_ADDRESS"
    return
  fi

  echo "  Setting subgraph availability oracle to $ORACLE_ADDRESS..."
  cast send --rpc-url "$HARDHAT_RPC" \
    --private-key "$ACCOUNT1_SECRET" \
    "$REWARDS_MANAGER_ADDRESS" \
    "setSubgraphAvailabilityOracle(address)" "$ORACLE_ADDRESS" \
    --confirmations 1 > /dev/null 2>&1

  echo "  OK    Subgraph availability oracle set"
}

# Deny a subgraph deployment.
# Args: $1 = deployment bytes32
deny_subgraph() {
  local deployment_bytes32="$1"
  echo "  Denying subgraph $deployment_bytes32..."
  cast send --rpc-url "$HARDHAT_RPC" \
    --private-key "$ORACLE_SECRET" \
    "$REWARDS_MANAGER_ADDRESS" \
    "setDenied(bytes32,bool)" "$deployment_bytes32" true \
    --confirmations 1 > /dev/null 2>&1
}

# Undeny a subgraph deployment.
# Args: $1 = deployment bytes32
undeny_subgraph() {
  local deployment_bytes32="$1"
  echo "  Undenying subgraph $deployment_bytes32..."
  cast send --rpc-url "$HARDHAT_RPC" \
    --private-key "$ORACLE_SECRET" \
    "$REWARDS_MANAGER_ADDRESS" \
    "setDenied(bytes32,bool)" "$deployment_bytes32" false \
    --confirmations 1 > /dev/null 2>&1
}

# Check if a subgraph is denied.
# Args: $1 = deployment bytes32
# Returns: 0 if denied, 1 if not
is_subgraph_denied() {
  local deployment_bytes32="$1"
  local result
  result=$(cast call --rpc-url "$HARDHAT_RPC" \
    "$REWARDS_MANAGER_ADDRESS" "isDenied(bytes32)(bool)" "$deployment_bytes32")
  [ "$result" = "true" ]
}

# Get the allocated tokens for an allocation from SubgraphService.
# Args: $1 = allocation ID (address)
# Returns: token amount (uint256) on stdout
get_allocation_tokens() {
  local allocation_id="$1"
  # getAllocation returns: (address indexer, bytes32 deploymentID, uint256 tokens, uint256 createdAt, ...)
  local result
  result=$(cast call --rpc-url "$HARDHAT_RPC" \
    "$SUBGRAPH_SERVICE_ADDRESS" "getAllocation(address)((address,bytes32,uint256,uint256,uint256,uint256,uint256,uint256))" "$allocation_id")
  # tokens is the 3rd field (after indexer and deploymentID)
  echo "$result" | sed 's/[()]//g' | cut -d',' -f3 | sed 's/ *\[.*//; s/^ *//'
}

# Find the most recent active allocation ID for a deployment via the network subgraph.
# Args: $1 = deployment IPFS hash
# Returns: allocation ID on stdout, or empty if not found
find_allocation_for_deployment() {
  local deployment_hash="$1"
  local result
  result=$(curl -s --max-time 10 "$NETWORK_SUBGRAPH_URL" \
    -H 'content-type: application/json' \
    -d "{\"query\": \"{ allocations(where: { subgraphDeployment_: { ipfsHash: \\\"$deployment_hash\\\" }, status: Active }, orderBy: createdAt, orderDirection: desc, first: 1) { id } }\"}")
  echo "$result" | jq -r '.data.allocations[0].id // empty'
}

# Close an active allocation for a deployment (used for cleanup).
# Args: $1 = deployment IPFS hash
# Idempotent: no-op if no active allocation found.
close_allocation_for_deployment() {
  local deployment_hash="$1"
  local alloc_id
  alloc_id=$(find_allocation_for_deployment "$deployment_hash")
  if [ -z "$alloc_id" ]; then
    return
  fi
  echo "  Closing allocation $alloc_id for $deployment_hash..."
  cast send --rpc-url "$HARDHAT_RPC" --private-key "$RECEIVER_SECRET" \
    "$SUBGRAPH_SERVICE_ADDRESS" "stopService(address,bytes)" \
    "$RECEIVER_ADDRESS" "$(cast abi-encode 'f(address)' "$alloc_id")" \
    --confirmations 1 > /dev/null 2>&1 || true
}

# ── Collection helpers (PLAN_04 scenarios) ─────────────────────────

# Advance hardhat time by N seconds and mine a block.
# Args: $1 = seconds to advance
advance_time() {
  local seconds="$1"
  curl -sf "$HARDHAT_RPC" \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"evm_increaseTime\",\"params\":[$seconds],\"id\":1}" \
    > /dev/null
  cast rpc --rpc-url="$HARDHAT_RPC" evm_mine > /dev/null
}

# Compute the agreement ID from RCA parameters.
# Args: $1=payer, $2=dataService, $3=serviceProvider, $4=deadline, $5=nonce
# Outputs: bytes16 agreement ID (0x-prefixed)
get_agreement_id() {
  local payer="$1"
  local data_service="$2"
  local service_provider="$3"
  local deadline="$4"
  local nonce="$5"

  cast call --rpc-url "$HARDHAT_RPC" \
    "$RECURRING_COLLECTOR_ADDRESS" \
    "generateAgreementId(address,address,address,uint64,uint256)(bytes16)" \
    "$payer" "$data_service" "$service_provider" "$deadline" "$nonce"
}

# Get the lastCollectionAt timestamp for an agreement.
# Args: $1 = agreement ID (bytes16, 0x-prefixed)
# Outputs: lastCollectionAt as decimal string
get_last_collection_at() {
  local agreement_id="$1"

  # getAgreement returns a struct; lastCollectionAt is the 5th field
  local result
  result=$(cast call --rpc-url "$HARDHAT_RPC" \
    "$RECURRING_COLLECTOR_ADDRESS" \
    "getAgreement(bytes16)(address,address,address,uint64,uint64,uint64,uint256,uint256,uint32,uint32,uint32,uint64,uint8)" \
    "$agreement_id")

  # lastCollectionAt is the 5th value (0-indexed: field index 4)
  echo "$result" | sed -n '5p'
}

# Get the state of an agreement.
# Args: $1 = agreement ID (bytes16, 0x-prefixed)
# Outputs: state as decimal (0=NotAccepted, 1=Accepted, 2=CanceledBySP, 3=CanceledByPayer)
get_agreement_state() {
  local agreement_id="$1"

  local result
  result=$(cast call --rpc-url "$HARDHAT_RPC" \
    "$RECURRING_COLLECTOR_ADDRESS" \
    "getAgreement(bytes16)(address,address,address,uint64,uint64,uint64,uint256,uint256,uint32,uint32,uint32,uint64,uint8)" \
    "$agreement_id")

  # state is the 13th value (last field)
  echo "$result" | sed -n '13p'
}

# Cancel an agreement as the payer.
# Args: $1 = agreement ID (bytes16, 0x-prefixed)
cancel_agreement() {
  local agreement_id="$1"

  cast send --rpc-url "$HARDHAT_RPC" --private-key "$ACCOUNT0_SECRET" \
    "$RECURRING_COLLECTOR_ADDRESS" \
    "cancel(bytes16,uint8)" \
    "$agreement_id" 1 \
    --confirmations 1 > /dev/null 2>&1
}

# Ensure the allocation for a deployment is clean (no existing agreement).
# If the allocation already has an agreement, close it and wait for a new one.
# Args: $1 = deployment IPFS hash
ensure_clean_allocation() {
  local deployment_ipfs="$1"

  # Get current allocation ID from the network subgraph
  local alloc_result
  alloc_result=$(curl -s --max-time 10 "$NETWORK_SUBGRAPH_URL" \
    -H 'content-type: application/json' \
    -d "{\"query\": \"{ allocations(where: { subgraphDeployment_: { ipfsHash: \\\"$deployment_ipfs\\\" }, status: Active }) { id } }\"}")

  local alloc_id
  alloc_id=$(echo "$alloc_result" | jq -r '.data.allocations[0].id // empty')

  if [ -z "$alloc_id" ]; then
    echo "  ...   No active allocation, waiting for agent to create one..."
    local elapsed=0
    while [ "$elapsed" -lt 180 ]; do
      sleep 5
      elapsed=$((elapsed + 5))
      alloc_result=$(curl -s --max-time 10 "$NETWORK_SUBGRAPH_URL" \
        -H 'content-type: application/json' \
        -d "{\"query\": \"{ allocations(where: { subgraphDeployment_: { ipfsHash: \\\"$deployment_ipfs\\\" }, status: Active }) { id } }\"}")
      alloc_id=$(echo "$alloc_result" | jq -r '.data.allocations[0].id // empty')
      if [ -n "$alloc_id" ]; then
        echo "  OK    New allocation created: $alloc_id"
        return 0
      fi
    done
    echo "  WARN  Timed out waiting for allocation"
    return 1
  fi

  # Check if any non-canceled agreement exists for this allocation
  local agreement_result
  agreement_result=$(curl -s --max-time 10 "$NETWORK_SUBGRAPH_URL" \
    -H 'content-type: application/json' \
    -d "{\"query\": \"{ indexingAgreements(where: { allocationId: \\\"$alloc_id\\\", state_in: [1, 3] }) { id } }\"}")

  local has_agreement
  has_agreement=$(echo "$agreement_result" | jq -r '.data.indexingAgreements[0].id // empty')

  if [ -n "$has_agreement" ]; then
    echo "  ...   Allocation $alloc_id has existing agreement $has_agreement, closing..."
    cast send --rpc-url "$HARDHAT_RPC" --private-key "$RECEIVER_SECRET" \
      "$SUBGRAPH_SERVICE_ADDRESS" "stopService(address,bytes)" \
      "$RECEIVER_ADDRESS" "$(cast abi-encode 'f(address)' "$alloc_id")" \
      --confirmations 1 > /dev/null 2>&1

    # Wait for agent to create a new allocation
    local elapsed=0
    while [ "$elapsed" -lt 180 ]; do
      sleep 5
      elapsed=$((elapsed + 5))
      alloc_result=$(curl -s --max-time 10 "$NETWORK_SUBGRAPH_URL" \
        -H 'content-type: application/json' \
        -d "{\"query\": \"{ allocations(where: { subgraphDeployment_: { ipfsHash: \\\"$deployment_ipfs\\\" }, status: Active }) { id } }\"}")
      local new_alloc_id
      new_alloc_id=$(echo "$alloc_result" | jq -r '.data.allocations[0].id // empty')
      if [ -n "$new_alloc_id" ] && [ "$new_alloc_id" != "$alloc_id" ]; then
        echo "  OK    Fresh allocation created: $new_alloc_id"
        return 0
      fi
    done
    echo "  WARN  Timed out waiting for fresh allocation"
    return 1
  fi

  echo "  OK    Allocation $alloc_id is clean (no agreement)"
  return 0
}

# Ensure the network subgraph is running (resume if paused).
# The agent may pause the subgraph during restart (scenario 6).
ensure_network_subgraph_running() {
  local network_subgraph_id
  network_subgraph_id=$(curl -s http://${GRAPH_NODE_HOST:-localhost}:${GRAPH_NODE_GRAPHQL_PORT:-8000}/subgraphs/name/graph-network \
    -H 'content-type: application/json' \
    -d '{"query":"{ _meta { deployment } }"}' | jq -r '.data._meta.deployment')

  if [ -z "$network_subgraph_id" ] || [ "$network_subgraph_id" = "null" ]; then
    echo "  WARN  Could not determine network subgraph deployment ID"
    return
  fi

  # Resume via graph-node JSON-RPC
  docker exec graph-node curl -sf -X POST http://localhost:8020 \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"subgraph_resume\",\"params\":{\"deployment\":\"$network_subgraph_id\"},\"id\":1}" \
    > /dev/null 2>&1 || true
}

# Wait for the network subgraph to sync to chain head.
# Args: $1 = timeout (optional, default 60)
wait_subgraph_sync() {
  local timeout="${1:-60}"
  local elapsed=0
  local interval=5

  while [ "$elapsed" -lt "$timeout" ]; do
    local status
    status=$(curl -s "http://${GRAPH_NODE_HOST:-localhost}:${GRAPH_NODE_STATUS_PORT:-8030}/graphql" \
      -H 'content-type: application/json' \
      -d '{"query":"{ indexingStatuses(subgraphs:[\"'"$(curl -s http://${GRAPH_NODE_HOST:-localhost}:${GRAPH_NODE_GRAPHQL_PORT:-8000}/subgraphs/name/graph-network -H \"content-type: application/json\" -d '{\"query\":\"{_meta{deployment}}\"}' | jq -r '.data._meta.deployment')"'\"]) { chains { latestBlock { number } chainHeadBlock { number } } } }"}')
    local latest chain_head
    latest=$(echo "$status" | jq -r '.data.indexingStatuses[0].chains[0].latestBlock.number // "0"')
    chain_head=$(echo "$status" | jq -r '.data.indexingStatuses[0].chains[0].chainHeadBlock.number // "0"')
    if [ "$latest" = "$chain_head" ] && [ "$latest" != "0" ]; then
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  return 1
}

# Poll until lastCollectionAt changes from an initial value.
# Args: $1 = agreement ID, $2 = initial lastCollectionAt, $3 = timeout (optional)
# Returns: 0 if changed, 1 if timeout
poll_collection() {
  local agreement_id="$1"
  local initial_value="$2"
  local timeout="${3:-300}"
  local elapsed=0
  local interval=5

  while [ "$elapsed" -lt "$timeout" ]; do
    local current
    current=$(get_last_collection_at "$agreement_id")
    if [ "$current" != "$initial_value" ] && [ -n "$current" ]; then
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  return 1
}

# ── Prerequisites ─────────────────────────────────────────────────────

echo "=== DIPs Integration Tests ==="
echo "  Agent:    $AGENT_URL"
echo "  Postgres: $PG_HOST:$PG_PORT/$PG_DB"
echo ""

echo "--- Prerequisites ---"

check "psql reachable" \
  "$PGCMD -c 'SELECT 1;'" || { echo "FATAL: Cannot reach postgres"; exit 1; }

check "cast available" \
  "command -v cast" || { echo "FATAL: cast (foundry) not found"; exit 1; }

check "jq available" \
  "command -v jq" || { echo "FATAL: jq not found"; exit 1; }

check "python3 base58 available" \
  "python3 -c 'import base58'" || { echo "FATAL: python3 base58 not found (pip install base58)"; exit 1; }

check "agent healthy" \
  "gql '$AGENT_URL' '{ indexingRules(merged: false) { identifier } }' | jq -e '.data'" \
  || { echo "FATAL: Agent not responding"; exit 1; }

check "pending_rca_proposals table exists" \
  "$PGCMD -c \"SELECT 1 FROM pending_rca_proposals LIMIT 0;\"" \
  || { echo "FATAL: Table pending_rca_proposals does not exist. Run migration 23."; exit 1; }

# Oracle setup for deny/undeny scenarios
if [ -n "$ORACLE_ADDRESS" ] && [ -n "$ORACLE_SECRET" ]; then
  ensure_subgraph_availability_oracle
else
  echo "  SKIP  ORACLE_ADDRESS/ORACLE_SECRET not set (deny/undeny scenarios will be skipped)"
fi

echo ""

# ── Scenario helpers ──────────────────────────────────────────────────

# A deployment bytes32 that is NOT currently being indexed.
# This is a deterministic fake — no real subgraph, but that's fine for rule creation tests.
NEW_DEPLOYMENT_BYTES32="0x0100000000000000000000000000000000000000000000000000000000000001"
# Convert to IPFS hash for management API queries.
# For a real test with add-subgraph.sh, replace this with the actual deployment hash.
# For now we compute it: base58(0x1220 + bytes32_without_prefix)
NEW_DEPLOYMENT_IPFS=$(bytes32_to_ipfs "$NEW_DEPLOYMENT_BYTES32")

# An existing deployment that already has a rule (from start-indexing).
EXISTING_DEPLOYMENT_IPFS=$(gql "$AGENT_URL" \
  "{ indexingRules(merged: false) { identifier identifierType decisionBasis } }" \
  | jq -r '.data.indexingRules[] | select(.identifierType == "deployment" and .decisionBasis == "always") | .identifier' \
  | head -1)

echo "  New deployment (bytes32): $NEW_DEPLOYMENT_BYTES32"
echo "  New deployment (IPFS):    $NEW_DEPLOYMENT_IPFS"
echo "  Existing deployment:      $EXISTING_DEPLOYMENT_IPFS"
echo ""

# ── Scenarios ─────────────────────────────────────────────────────────
#
# Scenarios 1-5, 7, 9 are batched: all proposals are inserted at once,
# then we wait for a single agent cycle to process them all. This avoids
# waiting for a separate loop cycle per scenario.
#
# Scenarios 6 and 8 run standalone (restart and valid on-chain accept).

run_rejection_batch() {
  echo "=== Batch: Rejection scenarios (1, 2, 3, 4, 5, 7, 9) ==="
  echo ""

  # ── Scenario variables ──

  # Scenario 1: new deployment, fake sig
  local s1_uuid="00000001-0001-0001-0001-000000000001"

  # Scenario 2: existing deployment, fake sig
  local s2_uuid="00000002-0002-0002-0002-000000000002"
  local s2_bytes32=""
  if [ -n "$EXISTING_DEPLOYMENT_IPFS" ]; then
    s2_bytes32=$(ipfs_to_bytes32 "$EXISTING_DEPLOYMENT_IPFS")
  fi

  # Scenario 3: good + corrupt payload
  local s3_good_uuid="00000003-0003-0003-0003-000000000001"
  local s3_bad_uuid="00000003-0003-0003-0003-000000000002"
  local s3_deployment="0x0200000000000000000000000000000000000000000000000000000000000003"
  local s3_ipfs
  s3_ipfs=$(bytes32_to_ipfs "$s3_deployment")

  # Scenario 4: blocklisted deployment
  local s4_uuid="00000004-0004-0004-0004-000000000004"
  local s4_deployment="0x0300000000000000000000000000000000000000000000000000000000000004"
  local s4_ipfs
  s4_ipfs=$(bytes32_to_ipfs "$s4_deployment")

  # Scenario 5: duplicate proposals
  local s5_uuid1="00000005-0005-0005-0005-000000000001"
  local s5_uuid2="00000005-0005-0005-0005-000000000002"
  local s5_deployment="0x0400000000000000000000000000000000000000000000000000000000000005"
  local s5_ipfs
  s5_ipfs=$(bytes32_to_ipfs "$s5_deployment")

  # Scenario 7: expired deadline
  local s7_uuid="00000007-0007-0007-0007-000000000007"
  local s7_deployment="0x0600000000000000000000000000000000000000000000000000000000000007"
  local s7_ipfs
  s7_ipfs=$(bytes32_to_ipfs "$s7_deployment")

  # Scenario 9: invalid sig revert
  local s9_uuid="00000009-0009-0009-0009-000000000009"
  local s9_deployment="0x0700000000000000000000000000000000000000000000000000000000000009"
  local s9_ipfs
  s9_ipfs=$(bytes32_to_ipfs "$s9_deployment")

  # ── Cleanup ──

  cleanup_proposal "$s1_uuid" "$NEW_DEPLOYMENT_IPFS"
  cleanup_proposal "$s2_uuid"
  cleanup_proposal "$s3_good_uuid" "$s3_ipfs"
  cleanup_proposal "$s3_bad_uuid"
  cleanup_proposal "$s4_uuid" "$s4_ipfs"
  cleanup_proposal "$s5_uuid1" "$s5_ipfs"
  cleanup_proposal "$s5_uuid2"
  cleanup_proposal "$s7_uuid" "$s7_ipfs"
  cleanup_proposal "$s9_uuid" "$s9_ipfs"

  # ── Setup & Insert ──

  echo "  Inserting all proposals..."

  # S1: new deployment
  insert_proposal "$s1_uuid" "$(encode_rca "$NEW_DEPLOYMENT_BYTES32")"

  # S2: existing deployment
  if [ -n "$s2_bytes32" ]; then
    insert_proposal "$s2_uuid" "$(encode_rca "$s2_bytes32")"
  fi

  # S3: good + corrupt
  insert_proposal "$s3_good_uuid" "$(encode_rca "$s3_deployment")"
  $PGCMD -c "INSERT INTO pending_rca_proposals (id, signed_payload, version, status, created_at, updated_at)
    VALUES ('$s3_bad_uuid', E'\\\\xdeadbeef', 2, 'pending', NOW(), NOW());"

  # S4: blocklisted (set NEVER rule first)
  gql "$AGENT_URL" "mutation { setIndexingRule(rule: { identifier: \\\"$s4_ipfs\\\", identifierType: deployment, decisionBasis: never, protocolNetwork: \\\"hardhat\\\" }) { identifier } }" > /dev/null
  insert_proposal "$s4_uuid" "$(encode_rca "$s4_deployment")"

  # S5: duplicate proposals
  local s5_payload
  s5_payload=$(encode_rca "$s5_deployment")
  insert_proposal "$s5_uuid1" "$s5_payload"
  insert_proposal "$s5_uuid2" "$s5_payload"

  # S7: expired deadline
  local s7_expired=$(( $(date +%s) - 100 ))
  local s7_terms s7_metadata
  s7_terms=$(cast abi-encode "f((uint256,uint256))" "(1000,50)")
  s7_metadata=$(cast abi-encode "f((bytes32,uint8,bytes))" "($s7_deployment,1,$s7_terms)")
  insert_proposal "$s7_uuid" "$(cast abi-encode \
    "f(((uint64,uint64,address,address,address,uint256,uint256,uint32,uint32,uint256,bytes),bytes))" \
    "(($s7_expired,2000000000,${ACCOUNT0_ADDRESS},${RECEIVER_ADDRESS},${RECEIVER_ADDRESS},10000,100,3600,86400,42,$s7_metadata),0xaabbccdd)")"

  # S9: fake sig, future deadline
  local s9_deadline=$(( $(date +%s) + 7200 ))
  local s9_terms s9_metadata
  s9_terms=$(cast abi-encode "f((uint256,uint256))" "(1000,50)")
  s9_metadata=$(cast abi-encode "f((bytes32,uint8,bytes))" "($s9_deployment,1,$s9_terms)")
  insert_proposal "$s9_uuid" "$(cast abi-encode \
    "f(((uint64,uint64,address,address,address,uint256,uint256,uint32,uint32,uint256,bytes),bytes))" \
    "(($s9_deadline,2000000000,${ACCOUNT0_ADDRESS},${RECEIVER_ADDRESS},${RECEIVER_ADDRESS},10000,100,3600,86400,42,$s9_metadata),0xaabbccdd)")"

  echo "  All proposals inserted, waiting for agent cycle..."

  # ── Wait for agent to process ──
  # Poll scenario 1 as sentinel — once it's rejected, the cycle has run.
  poll_proposal_status "$s1_uuid" "rejected" 120

  # ── Check results ──
  echo ""

  echo "--- Scenario 1: New deployment — RCA processed by agent ---"
  check "1.1 Proposal rejected (fake signature)" \
    "check_proposal_status '$s1_uuid' 'rejected'" || true

  echo "--- Scenario 2: Existing deployment — proposal processed ---"
  if [ -n "$s2_bytes32" ]; then
    check "2.1 Proposal rejected (fake signature, existing allocation)" \
      "check_proposal_status '$s2_uuid' 'rejected'" || true
  else
    echo "  SKIP  No existing deployment found"
  fi

  echo "--- Scenario 3: Corrupt payload — agent skips bad rows ---"
  check "3.1 Valid proposal rejected (fake signature)" \
    "check_proposal_status '$s3_good_uuid' 'rejected'" || true
  check "3.2 Corrupt proposal still pending (not crashed)" \
    "check_proposal_status '$s3_bad_uuid' 'pending'" || true

  echo "--- Scenario 4: Blocklisted deployment — proposal rejected ---"
  check "4.1 Proposal rejected for blocklisted deployment" \
    "check_proposal_status '$s4_uuid' 'rejected'" || true

  echo "--- Scenario 5: Duplicate proposals — both processed ---"
  check "5.1 First proposal rejected" \
    "check_proposal_status '$s5_uuid1' 'rejected'" || true
  check "5.2 Second proposal rejected" \
    "check_proposal_status '$s5_uuid2' 'rejected'" || true

  echo "--- Scenario 7: Expired deadline — proposal rejected ---"
  check "7.1 Proposal rejected with expired deadline" \
    "check_proposal_status '$s7_uuid' 'rejected'" || true
  local s7_dips_count
  s7_dips_count=$(count_dips_rules "$s7_ipfs")
  check "7.2 No DIPS rule left for expired proposal" \
    "[ '$s7_dips_count' -eq 0 ]" || true

  echo "--- Scenario 9: Invalid signature — contract revert → rejected ---"
  check "9.1 Proposal rejected after contract revert" \
    "check_proposal_status '$s9_uuid' 'rejected'" || true
  local s9_dips_count
  s9_dips_count=$(count_dips_rules "$s9_ipfs")
  check "9.2 DIPS rule cleaned up after rejection" \
    "[ '$s9_dips_count' -eq 0 ]" || true

  # ── Cleanup all ──
  echo ""
  echo "  Cleaning up..."
  cleanup_proposal "$s1_uuid" "$NEW_DEPLOYMENT_IPFS"
  cleanup_proposal "$s2_uuid"
  cleanup_proposal "$s3_good_uuid" "$s3_ipfs"
  cleanup_proposal "$s3_bad_uuid"
  cleanup_proposal "$s4_uuid" "$s4_ipfs"
  cleanup_proposal "$s5_uuid1" "$s5_ipfs"
  cleanup_proposal "$s5_uuid2"
  cleanup_proposal "$s7_uuid" "$s7_ipfs"
  cleanup_proposal "$s9_uuid" "$s9_ipfs"
  echo ""
}

scenario_6_agent_restart() {
  echo "=== Scenario 6: Agent restart — proposals survive and get processed ==="
  local uuid="00000006-0006-0006-0006-000000000006"
  local deployment="0x0500000000000000000000000000000000000000000000000000000000000006"
  local ipfs
  ipfs=$(bytes32_to_ipfs "$deployment")

  cleanup_proposal "$uuid" "$ipfs"

  insert_proposal "$uuid" "$(encode_rca "$deployment")"

  echo "  Inserted proposal, reloading agent..."
  docker exec indexer-agent touch /opt/indexer-agent-source-root/packages/indexer-agent/src/index.ts 2>/dev/null \
    || echo "  (Could not trigger reload via touch)"

  sleep 15
  local elapsed=0
  while [ "$elapsed" -lt 60 ]; do
    if gql "$AGENT_URL" "{ indexingRules(merged: false) { identifier } }" | jq -e '.data' > /dev/null 2>&1; then
      break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  check "6.1 Proposal processed after restart" \
    "poll_proposal_status '$uuid' 'rejected' 120" || true

  cleanup_proposal "$uuid" "$ipfs"
  echo ""
}

scenario_8_onchain_accept_and_collect() {
  echo "=== Scenario 8: Valid on-chain accept + collection ==="

  # Use an existing indexed deployment so Graph Node can produce POI for collection.
  local deployment_ipfs
  deployment_ipfs=$(gql "$AGENT_URL" \
    "{ indexingRules(merged: false) { identifier identifierType decisionBasis } }" \
    | jq -r '.data.indexingRules[] | select(.identifierType == "deployment" and .decisionBasis == "always") | .identifier' \
    | head -1)

  if [ -z "$deployment_ipfs" ] || [ "$deployment_ipfs" = "null" ]; then
    echo "  SKIP  No existing deployment with 'always' rule found"
    return
  fi

  local deployment_bytes32
  deployment_bytes32=$(ipfs_to_bytes32 "$deployment_ipfs")

  local uuid="00000008-0008-0008-0008-000000000008"

  # Only clean up the proposal row; do NOT pass deployment_ipfs to avoid
  # deleting the "always" indexing rule that keeps the allocation open.
  cleanup_proposal "$uuid"
  ensure_payer_escrow
  ensure_signer_authorized

  # Ensure the network subgraph is running (may be paused after scenario 6 restart)
  ensure_network_subgraph_running

  # Ensure the allocation has no existing agreement (idempotent re-runs)
  ensure_clean_allocation "$deployment_ipfs" || {
    echo "  SKIP  Could not get clean allocation for $deployment_ipfs"
    return
  }

  local ts
  ts=$(date +%s)
  local deadline=$(( ts + 7200 ))
  local ends_at=$(( ts + 172800 ))
  local nonce
  nonce=$(date +%s%N)
  local payload
  payload=$(encode_signed_rca "$deployment_bytes32" "$deadline" "$ends_at" "$nonce")

  if [ -z "$payload" ] || [ "$payload" = "" ]; then
    echo "  SKIP  Failed to encode signed RCA"
    return
  fi

  # Compute agreement ID from the params used in encode_signed_rca
  local agreement_id
  agreement_id=$(get_agreement_id \
    "$ACCOUNT0_ADDRESS" "$SUBGRAPH_SERVICE_ADDRESS" "$RECEIVER_ADDRESS" \
    "$deadline" "$nonce")

  insert_proposal "$uuid" "$payload"
  echo "  Inserted signed proposal for $deployment_ipfs (existing allocation), waiting for acceptance..."

  # Phase 1: Acceptance
  check "8.1 Proposal accepted on-chain" \
    "poll_proposal_status '$uuid' 'accepted' 180" || {
    echo "  Acceptance failed, skipping collection checks"
    cleanup_proposal "$uuid"
    return
  }

  # Phase 2: Collection
  echo "  Agreement accepted. Advancing time for collection..."

  # Record initial lastCollectionAt (should equal acceptedAt)
  local initial_last_collected
  initial_last_collected=$(get_last_collection_at "$agreement_id")
  echo "  Initial lastCollectionAt: $initial_last_collected"

  # Advance time past minSecondsPerCollection (3600s in our terms)
  advance_time 3700
  echo "  Advanced time by 3700s. Waiting for subgraph sync and agent collection loop..."

  # Mine extra blocks and wait for the network subgraph to catch up
  ~/.foundry/bin/cast rpc --rpc-url="$HARDHAT_RPC" evm_mine > /dev/null
  wait_subgraph_sync 60 || echo "  WARN  Subgraph sync timed out"

  # Wait for the agent to collect
  check "8.2 Payment collected (lastCollectionAt updated)" \
    "poll_collection '$agreement_id' '$initial_last_collected' 300" || true

  cleanup_proposal "$uuid"
  echo ""
}

scenario_10_collection_after_cancel() {
  echo "=== Scenario 10: Collection after payer cancellation ==="

  # Use an existing indexed deployment (same approach as scenario 8).
  local deployment_ipfs
  deployment_ipfs=$(gql "$AGENT_URL" \
    "{ indexingRules(merged: false) { identifier identifierType decisionBasis } }" \
    | jq -r '.data.indexingRules[] | select(.identifierType == "deployment" and .decisionBasis == "always") | .identifier' \
    | head -1)

  if [ -z "$deployment_ipfs" ] || [ "$deployment_ipfs" = "null" ]; then
    echo "  SKIP  No existing deployment with 'always' rule found"
    return
  fi

  local deployment_bytes32
  deployment_bytes32=$(ipfs_to_bytes32 "$deployment_ipfs")

  local uuid="00000010-0010-0010-0010-000000000010"

  # Only clean up the proposal row; preserve the "always" indexing rule.
  cleanup_proposal "$uuid"
  ensure_payer_escrow
  ensure_signer_authorized

  ensure_network_subgraph_running

  # Ensure the allocation has no existing agreement (idempotent re-runs)
  ensure_clean_allocation "$deployment_ipfs" || {
    echo "  SKIP  Could not get clean allocation for $deployment_ipfs"
    return
  }

  local ts
  ts=$(date +%s)
  local deadline=$(( ts + 7200 ))
  local ends_at=$(( ts + 172800 ))
  local nonce
  nonce=$(date +%s%N)
  local payload
  payload=$(encode_signed_rca "$deployment_bytes32" "$deadline" "$ends_at" "$nonce")

  if [ -z "$payload" ] || [ "$payload" = "" ]; then
    echo "  SKIP  Failed to encode signed RCA"
    return
  fi

  local agreement_id
  agreement_id=$(get_agreement_id \
    "$ACCOUNT0_ADDRESS" "$SUBGRAPH_SERVICE_ADDRESS" "$RECEIVER_ADDRESS" \
    "$deadline" "$nonce")

  insert_proposal "$uuid" "$payload"
  echo "  Inserted signed proposal for $deployment_ipfs, waiting for acceptance..."

  # Step 1: Wait for acceptance
  check "10.1 Proposal accepted on-chain" \
    "poll_proposal_status '$uuid' 'accepted' 180" || {
    echo "  Acceptance failed, skipping cancellation/collection checks"
    cleanup_proposal "$uuid"
    return
  }

  # Step 2: Advance time past minSecondsPerCollection
  echo "  Agreement accepted. Advancing time before cancellation..."
  advance_time 3700

  # Step 3: Payer cancels the agreement
  echo "  Canceling agreement as payer..."
  cancel_agreement "$agreement_id"

  # Verify cancellation happened
  local state_after_cancel
  state_after_cancel=$(get_agreement_state "$agreement_id")
  check "10.2 Agreement state is CanceledByPayer (3)" \
    "[ '$state_after_cancel' = '3' ]" || {
    echo "  Cancellation check failed (state=$state_after_cancel)"
    cleanup_proposal "$uuid"
    return
  }

  # Step 4: Record lastCollectionAt before final collection
  local pre_collect_timestamp
  pre_collect_timestamp=$(get_last_collection_at "$agreement_id")
  echo "  Pre-collection lastCollectionAt: $pre_collect_timestamp"

  # Step 5: Advance time again so collection window opens
  advance_time 3700
  echo "  Advanced time again. Waiting for subgraph sync and agent collection..."

  # Mine extra blocks and wait for subgraph to catch up
  ~/.foundry/bin/cast rpc --rpc-url="$HARDHAT_RPC" evm_mine > /dev/null
  wait_subgraph_sync 60 || echo "  WARN  Subgraph sync timed out"

  # Step 6: Wait for the agent to collect from the canceled agreement
  # The agent queries state_in: [1, 3] so CanceledByPayer agreements are included.
  check "10.3 Final payment collected after cancellation" \
    "poll_collection '$agreement_id' '$pre_collect_timestamp' 300" || true

  cleanup_proposal "$uuid"
  echo ""
}

# Get the current chain block timestamp (accounts for time advances in hardhat).
# Falls back to real time if cast call fails.
get_chain_timestamp() {
  local ts
  ts=$(cast block --rpc-url "$HARDHAT_RPC" latest --json 2>/dev/null \
    | python3 -c "import json,sys; print(int(json.load(sys.stdin)['timestamp'],16))" 2>/dev/null)
  echo "${ts:-$(date +%s)}"
}

# ── Multicall accept + token amount scenarios (PLAN_03A) ─────────────

scenario_11_rewarded_new_allocation() {
  echo "=== Scenario 11: Rewarded subgraph — new allocation via multicall ==="

  local uuid="0000000b-000b-000b-000b-00000000000b"
  local deployment="0x0800000000000000000000000000000000000000000000000000000000000011"
  local ipfs
  ipfs=$(bytes32_to_ipfs "$deployment")

  # Clean slate — close any leftover allocation and remove proposal/rule
  cleanup_proposal "$uuid" "$ipfs"
  local had_alloc=""
  if find_allocation_for_deployment "$ipfs" | grep -q .; then
    had_alloc=1
    close_allocation_for_deployment "$ipfs"
  fi

  # Ensure deployment is NOT denied (fresh deployment shouldn't be, but be safe)
  if is_subgraph_denied "$deployment"; then
    undeny_subgraph "$deployment"
  fi

  ensure_payer_escrow
  ensure_signer_authorized
  ensure_network_subgraph_running

  # Wait for subgraph to reflect the closed allocation (only if we closed one)
  if [ -n "$had_alloc" ]; then
    wait_subgraph_sync 60 || true
  fi

  # Verify no active allocation exists
  local existing_alloc
  existing_alloc=$(find_allocation_for_deployment "$ipfs")
  if [ -n "$existing_alloc" ]; then
    echo "  WARN  Allocation $existing_alloc still active for $ipfs, multicall path may not trigger"
  fi

  # Create properly signed RCA (use chain time to account for time advances)
  local ts
  ts=$(get_chain_timestamp)
  local deadline=$(( ts + 7200 ))
  local ends_at=$(( ts + 172800 ))
  local nonce
  nonce=$(date +%s%N)
  local payload
  payload=$(encode_signed_rca "$deployment" "$deadline" "$ends_at" "$nonce" 2>/dev/null)

  if [ -z "$payload" ]; then
    echo "  SKIP  Failed to encode signed RCA"
    return
  fi

  insert_proposal "$uuid" "$payload"
  echo "  Inserted signed proposal for rewarded deployment (no existing allocation), waiting..."

  # Agent processes: getDipsAllocationAmount sees isDenied=false → defaultAllocationAmount
  # No existing allocation → multicall(startService + acceptIndexingAgreement)
  check "11.1 Proposal accepted on-chain (multicall path)" \
    "poll_proposal_status '$uuid' 'accepted' 300" || {
    echo "  Acceptance failed, skipping token amount check"
    cleanup_proposal "$uuid" "$ipfs"
    return
  }

  # Verify allocation was created with non-zero tokens (defaultAllocationAmount)
  wait_subgraph_sync 60 || true
  local alloc_id
  alloc_id=$(find_allocation_for_deployment "$ipfs")
  if [ -n "$alloc_id" ]; then
    local tokens
    tokens=$(get_allocation_tokens "$alloc_id")
    check "11.2 Allocation has non-zero tokens (defaultAllocationAmount)" \
      "[ '$tokens' != '0' ]" || true
    echo "  Allocation $alloc_id tokens: $tokens"
  else
    echo "  WARN  Could not find allocation for $ipfs to verify token amount"
  fi

  # Cleanup
  cleanup_proposal "$uuid" "$ipfs"
  close_allocation_for_deployment "$ipfs"
  echo ""
}

scenario_12_denied_dips_amount() {
  echo "=== Scenario 12: Denied subgraph — allocation with dipsAllocationAmount via multicall ==="
  if [ -z "$ORACLE_ADDRESS" ] || [ -z "$ORACLE_SECRET" ]; then
    echo "  SKIP  Oracle account not configured"
    return
  fi

  local uuid="0000000c-000c-000c-000c-00000000000c"
  local deployment="0x0900000000000000000000000000000000000000000000000000000000000012"
  local ipfs
  ipfs=$(bytes32_to_ipfs "$deployment")

  # Clean slate — close any leftover allocation and remove proposal/rule
  cleanup_proposal "$uuid" "$ipfs"
  local had_alloc=""
  if find_allocation_for_deployment "$ipfs" | grep -q .; then
    had_alloc=1
    close_allocation_for_deployment "$ipfs"
  fi

  ensure_payer_escrow
  ensure_signer_authorized
  ensure_network_subgraph_running

  # Wait for subgraph to reflect the closed allocation (only if we closed one)
  if [ -n "$had_alloc" ]; then
    wait_subgraph_sync 60 || true
  fi

  # Deny the subgraph BEFORE inserting the proposal
  deny_subgraph "$deployment"
  check "12.0 Subgraph is denied" \
    "is_subgraph_denied '$deployment'" || { undeny_subgraph "$deployment"; return; }

  # Create properly signed RCA (use chain time to account for time advances)
  local ts
  ts=$(get_chain_timestamp)
  local deadline=$(( ts + 7200 ))
  local ends_at=$(( ts + 172800 ))
  local nonce
  nonce=$(date +%s%N)
  local payload
  payload=$(encode_signed_rca "$deployment" "$deadline" "$ends_at" "$nonce" 2>/dev/null)

  if [ -z "$payload" ]; then
    echo "  SKIP  Failed to encode signed RCA"
    undeny_subgraph "$deployment"
    return
  fi

  insert_proposal "$uuid" "$payload"
  echo "  Inserted signed proposal for denied deployment (no existing allocation), waiting..."

  # Agent processes: getDipsAllocationAmount sees isDenied=true → dipsAllocationAmount
  # No existing allocation → multicall(startService + acceptIndexingAgreement)
  check "12.1 Proposal accepted on-chain (multicall path, dipsAllocationAmount)" \
    "poll_proposal_status '$uuid' 'accepted' 300" || {
    echo "  Acceptance failed, skipping token amount check"
    undeny_subgraph "$deployment"
    cleanup_proposal "$uuid" "$ipfs"
    return
  }

  # Verify allocation was created with dipsAllocationAmount (default 0 = altruistic)
  wait_subgraph_sync 60 || true
  local alloc_id
  alloc_id=$(find_allocation_for_deployment "$ipfs")
  if [ -n "$alloc_id" ]; then
    local tokens
    tokens=$(get_allocation_tokens "$alloc_id")
    # dipsAllocationAmount is set via INDEXER_AGENT_DIPS_ALLOCATION_AMOUNT.
    # Verify tokens differ from defaultAllocationAmount (non-denied subgraphs use that).
    check "12.2 Allocation uses dipsAllocationAmount (not defaultAllocationAmount)" \
      "[ '$tokens' != '10000000000000000' ]" || true
    echo "  Allocation $alloc_id tokens: $tokens"
  else
    echo "  WARN  Could not find allocation for $ipfs to verify token amount"
  fi

  # Cleanup
  undeny_subgraph "$deployment"
  cleanup_proposal "$uuid" "$ipfs"
  close_allocation_for_deployment "$ipfs"
  echo ""
}

# ── Run ───────────────────────────────────────────────────────────────

run_rejection_batch
scenario_6_agent_restart
# TODO: enable once on-chain collect is implemented (Task 4)
# scenario_8_onchain_accept_and_collect
# scenario_10_collection_after_cancel

# PLAN_03A scenarios (multicall path + token amount) — run in parallel
s11_results=$(mktemp /tmp/dips-s11-XXXXXX)
s12_results=$(mktemp /tmp/dips-s12-XXXXXX)

(
  pass=0; fail=0; total=0
  scenario_11_rewarded_new_allocation
  echo "$pass $fail $total" > "$s11_results"
) &
pid_s11=$!

(
  pass=0; fail=0; total=0
  scenario_12_denied_dips_amount
  echo "$pass $fail $total" > "$s12_results"
) &
pid_s12=$!

wait $pid_s11
wait $pid_s12

# Merge parallel results into main counters
read s11_p s11_f s11_t < "$s11_results"
pass=$((pass + s11_p)); fail=$((fail + s11_f)); total=$((total + s11_t))
read s12_p s12_f s12_t < "$s12_results"
pass=$((pass + s12_p)); fail=$((fail + s12_f)); total=$((total + s12_t))
rm -f "$s11_results" "$s12_results"

# ── Summary ───────────────────────────────────────────────────────────

echo "=== Results ==="
echo "  $pass passed, $fail failed, $total total"

if [ "$fail" -eq 0 ]; then
  echo "  All DIPs integration tests passed."
  exit 0
else
  echo "  Some tests failed."
  exit 1
fi
