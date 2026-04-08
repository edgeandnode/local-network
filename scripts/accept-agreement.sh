#!/usr/bin/env bash
set -euo pipefail

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../.env"

# RPC endpoint
RPC="http://${CHAIN_HOST:-localhost}:${CHAIN_RPC_PORT:-8545}"

# Accounts
INDEXER_ADDRESS="$RECEIVER_ADDRESS"
INDEXER_SECRET="$RECEIVER_SECRET"
PAYER_ADDRESS="$ACCOUNT0_ADDRESS"
PAYER_SECRET="$ACCOUNT0_SECRET"

# Contract addresses (read from config)
SUBGRAPH_SERVICE=$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/subgraph-service.json'))['1337']['SubgraphService']['address'])")
RECURRING_COLLECTOR=$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['RecurringCollector']['address'])")
PAYMENTS_ESCROW=$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['PaymentsEscrow']['address'])")
GRT_TOKEN=$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['L2GraphToken']['address'])")

echo "=== Accept Agreement Test Script ==="
echo ""
echo "RPC: $RPC"
echo "Indexer: $INDEXER_ADDRESS"
echo "Payer: $PAYER_ADDRESS"
echo "SubgraphService: $SUBGRAPH_SERVICE"
echo "RecurringCollector: $RECURRING_COLLECTOR"
echo "PaymentsEscrow: $PAYMENTS_ESCROW"
echo "GRT Token: $GRT_TOKEN"
echo ""

# Use an existing allocation
ALLOCATION_ID="0x26b3794d6ab70321bf8c751ab2fa0977fd31687e"
DEPLOYMENT_IPFS="QmfXY3tHTDdRGFG4pFfiCk9p3kZ44WhqJ1Mg46NbB6tvUE"
# Convert IPFS hash to bytes32
DEPLOYMENT_BYTES32=$(python3 -c "import base58; h=base58.b58decode('$DEPLOYMENT_IPFS').hex(); print('0x' + h[4:])")

echo "Using existing allocation: $ALLOCATION_ID"
echo "Deployment IPFS: $DEPLOYMENT_IPFS"
echo "Deployment bytes32: $DEPLOYMENT_BYTES32"
echo ""

# Step 1: Fund payer escrow
echo "=== Step 1: Fund Payer Escrow ==="
ESCROW_AMOUNT="1000000000000000000000"  # 1000 GRT

CURRENT_BALANCE=$(cast call --rpc-url "$RPC" \
  "$PAYMENTS_ESCROW" "getBalance(address,address,address)(uint256)" \
  "$PAYER_ADDRESS" "$RECURRING_COLLECTOR" "$INDEXER_ADDRESS" 2>/dev/null || echo "0")
echo "Current escrow balance: $CURRENT_BALANCE"

if [ "$CURRENT_BALANCE" = "0" ]; then
  echo "Approving GRT for escrow..."
  cast send --rpc-url "$RPC" --private-key "$PAYER_SECRET" \
    "$GRT_TOKEN" "approve(address,uint256)" \
    "$PAYMENTS_ESCROW" "$ESCROW_AMOUNT" \
    --confirmations 0 > /dev/null 2>&1

  echo "Depositing to escrow..."
  cast send --rpc-url "$RPC" --private-key "$PAYER_SECRET" \
    "$PAYMENTS_ESCROW" "deposit(address,address,uint256)" \
    "$RECURRING_COLLECTOR" "$INDEXER_ADDRESS" "$ESCROW_AMOUNT" \
    --confirmations 0 > /dev/null 2>&1

  NEW_BALANCE=$(cast call --rpc-url "$RPC" \
    "$PAYMENTS_ESCROW" "getBalance(address,address,address)(uint256)" \
    "$PAYER_ADDRESS" "$RECURRING_COLLECTOR" "$INDEXER_ADDRESS" 2>/dev/null || echo "0")
  echo "New escrow balance: $NEW_BALANCE"
else
  echo "Escrow already funded"
fi
echo ""

# Step 2: Authorize signer
echo "=== Step 2: Authorize Signer ==="
IS_AUTH=$(cast call --rpc-url "$RPC" \
  "$RECURRING_COLLECTOR" "isAuthorized(address,address)(bool)" \
  "$PAYER_ADDRESS" "$PAYER_ADDRESS" 2>/dev/null || echo "false")

if [ "$IS_AUTH" != "true" ]; then
  echo "Authorizing payer as signer..."
  CHAIN_ID=$(cast chain-id --rpc-url "$RPC")
  AUTH_DEADLINE=$(($(date +%s) + 86400))

  PACKED=$(cast abi-encode --packed \
    "f(uint256,address,string,uint256,address)" \
    "$CHAIN_ID" "$RECURRING_COLLECTOR" "authorizeSignerProof" "$AUTH_DEADLINE" "$PAYER_ADDRESS")
  HASH=$(cast keccak "$PACKED")
  PROOF=$(cast wallet sign --private-key "$PAYER_SECRET" "$HASH")

  cast send --rpc-url "$RPC" --private-key "$PAYER_SECRET" \
    "$RECURRING_COLLECTOR" "authorizeSigner(address,uint256,bytes)" \
    "$PAYER_ADDRESS" "$AUTH_DEADLINE" "$PROOF" \
    --confirmations 0 > /dev/null 2>&1

  IS_AUTH=$(cast call --rpc-url "$RPC" \
    "$RECURRING_COLLECTOR" "isAuthorized(address,address)(bool)" \
    "$PAYER_ADDRESS" "$PAYER_ADDRESS" 2>/dev/null || echo "false")
  echo "Authorization result: $IS_AUTH"
else
  echo "Signer already authorized"
fi
echo ""

# Step 3: Create and sign RCA
echo "=== Step 3: Create Signed RCA ==="

# Get chain time for deadline
CHAIN_TIME=$(cast block latest --rpc-url "$RPC" --json | jq -r '.timestamp')
CHAIN_TIME_DEC=$(printf "%d" "$CHAIN_TIME")
echo "Chain time: $CHAIN_TIME_DEC"

DEADLINE=$((CHAIN_TIME_DEC + 7200))  # 2 hours from chain time
ENDS_AT=$((CHAIN_TIME_DEC + 604800))  # 1 week
NONCE=$(date +%s%N)

echo "Deadline: $DEADLINE"
echo "EndsAt: $ENDS_AT"
echo "Nonce: $NONCE"

# Encode metadata: (bytes32 subgraphDeploymentId, uint8 version, bytes terms)
# Terms for V1: (uint256 tokensPerSecond, uint256 tokensPerEntityPerSecond)
TERMS=$(cast abi-encode "f((uint256,uint256))" "(50,10)")
METADATA=$(cast abi-encode "f((bytes32,uint8,bytes))" "($DEPLOYMENT_BYTES32,0,$TERMS)")
echo "Metadata: ${METADATA:0:100}..."

# Query EIP-712 domain from contract
echo ""
echo "Querying EIP-712 domain..."
DOMAIN_RESULT=$(cast call --rpc-url "$RPC" \
  "$RECURRING_COLLECTOR" \
  "eip712Domain()(bytes1,string,string,uint256,address,bytes32,uint256[])" 2>/dev/null) || true

if [ -n "$DOMAIN_RESULT" ]; then
  DOMAIN_NAME=$(echo "$DOMAIN_RESULT" | sed -n '2p' | tr -d '"')
  DOMAIN_VERSION=$(echo "$DOMAIN_RESULT" | sed -n '3p' | tr -d '"')
  DOMAIN_CHAIN_ID=$(echo "$DOMAIN_RESULT" | sed -n '4p')
  DOMAIN_CONTRACT=$(echo "$DOMAIN_RESULT" | sed -n '5p')
  echo "Domain from contract: name=$DOMAIN_NAME, version=$DOMAIN_VERSION, chainId=$DOMAIN_CHAIN_ID"
else
  DOMAIN_NAME="RecurringCollector"
  DOMAIN_VERSION="1"
  DOMAIN_CHAIN_ID=1337
  DOMAIN_CONTRACT="$RECURRING_COLLECTOR"
  echo "Using fallback domain: name=$DOMAIN_NAME, version=$DOMAIN_VERSION, chainId=$DOMAIN_CHAIN_ID"
fi

# Build EIP-712 typed data
TYPED_DATA_FILE=$(mktemp /tmp/rca-typed-data-XXXXXX.json)
cat > "$TYPED_DATA_FILE" <<EOFJSON
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
    "name": "$DOMAIN_NAME",
    "version": "$DOMAIN_VERSION",
    "chainId": $DOMAIN_CHAIN_ID,
    "verifyingContract": "$DOMAIN_CONTRACT"
  },
  "message": {
    "deadline": $DEADLINE,
    "endsAt": $ENDS_AT,
    "payer": "$PAYER_ADDRESS",
    "dataService": "$SUBGRAPH_SERVICE",
    "serviceProvider": "$INDEXER_ADDRESS",
    "maxInitialTokens": "10000",
    "maxOngoingTokensPerSecond": "100",
    "minSecondsPerCollection": 3600,
    "maxSecondsPerCollection": 86400,
    "nonce": "$NONCE",
    "metadata": "$METADATA"
  }
}
EOFJSON

echo ""
echo "Typed data written to: $TYPED_DATA_FILE"
echo "Message content:"
jq '.message' "$TYPED_DATA_FILE"

# Sign the typed data
echo ""
echo "Signing typed data..."
SIGNATURE=$(cast wallet sign --data --from-file --private-key "$PAYER_SECRET" "$TYPED_DATA_FILE")
echo "Signature: $SIGNATURE"

rm -f "$TYPED_DATA_FILE"
echo ""

# Step 4: Call acceptIndexingAgreement
echo "=== Step 4: Call acceptIndexingAgreement ==="
echo "Allocation: $ALLOCATION_ID"
echo ""
# The function signature uses the full struct tuple, not bytes
SIG="acceptIndexingAgreement(address,((uint64,uint64,address,address,address,uint256,uint256,uint32,uint32,uint256,bytes),bytes))"

# First try estimateGas to see the error
echo "Estimating gas (to see any revert reason)..."
cast estimate --rpc-url "$RPC" \
  --from "$INDEXER_ADDRESS" \
  "$SUBGRAPH_SERVICE" \
  "$SIG" \
  "$ALLOCATION_ID" \
  "(($DEADLINE,$ENDS_AT,$PAYER_ADDRESS,$SUBGRAPH_SERVICE,$INDEXER_ADDRESS,10000,100,3600,86400,$NONCE,$METADATA),$SIGNATURE)" 2>&1 || echo "(estimate failed)"

echo ""
echo "Sending transaction..."
cast send --rpc-url "$RPC" --private-key "$INDEXER_SECRET" \
  "$SUBGRAPH_SERVICE" \
  "$SIG" \
  "$ALLOCATION_ID" \
  "(($DEADLINE,$ENDS_AT,$PAYER_ADDRESS,$SUBGRAPH_SERVICE,$INDEXER_ADDRESS,10000,100,3600,86400,$NONCE,$METADATA),$SIGNATURE)" \
  2>&1

echo ""
echo "=== Done ==="
