#!/usr/bin/env bash
# Focused test: accept an agreement, advance time, call collect directly.
# Bypasses the agent entirely to isolate the contract interaction.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../.env"

RPC="http://${CHAIN_HOST:-localhost}:${CHAIN_RPC_PORT:-8545}"
export PATH="$HOME/.foundry/bin:$PATH"

# Accounts
INDEXER="$RECEIVER_ADDRESS"
INDEXER_SECRET="$RECEIVER_SECRET"
PAYER="$ACCOUNT0_ADDRESS"
PAYER_SECRET="$ACCOUNT0_SECRET"

# Contracts
SUBGRAPH_SERVICE=$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/subgraph-service.json'))['1337']['SubgraphService']['address'])")
RECURRING_COLLECTOR=$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['RecurringCollector']['address'])")
PAYMENTS_ESCROW=$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['PaymentsEscrow']['address'])")
GRT_TOKEN=$(docker exec indexer-agent python3 -c "import json; print(json.load(open('/opt/config/horizon.json'))['1337']['L2GraphToken']['address'])")

# Use an existing allocation (from start-indexing)
ALLOC_ID=$(curl -s "http://localhost:8000/subgraphs/name/graph-network" \
  -H 'content-type: application/json' \
  -d '{"query":"{ allocations(where:{status:Active}, first:1) { id subgraphDeployment { ipfsHash id } } }"}' \
  | jq -r '.data.allocations[0].id')
DEPLOY_IPFS=$(curl -s "http://localhost:8000/subgraphs/name/graph-network" \
  -H 'content-type: application/json' \
  -d '{"query":"{ allocations(where:{status:Active}, first:1) { id subgraphDeployment { ipfsHash id } } }"}' \
  | jq -r '.data.allocations[0].subgraphDeployment.ipfsHash')
DEPLOY_BYTES32=$(curl -s "http://localhost:8000/subgraphs/name/graph-network" \
  -H 'content-type: application/json' \
  -d '{"query":"{ allocations(where:{status:Active}, first:1) { id subgraphDeployment { ipfsHash id } } }"}' \
  | jq -r '.data.allocations[0].subgraphDeployment.id')

echo "=== Collection Test ==="
echo "RPC:               $RPC"
echo "Indexer:            $INDEXER"
echo "Payer:              $PAYER"
echo "SubgraphService:    $SUBGRAPH_SERVICE"
echo "RecurringCollector: $RECURRING_COLLECTOR"
echo "Allocation:         $ALLOC_ID"
echo "Deployment:         $DEPLOY_IPFS"
echo "Deployment bytes32: $DEPLOY_BYTES32"
echo ""

# ── Step 1: Fund escrow ──────────────────────────────────────────────
echo "--- Step 1: Fund escrow ---"
AMOUNT="1000000000000000000000"
cast send --rpc-url "$RPC" --private-key "$PAYER_SECRET" \
  "$GRT_TOKEN" "approve(address,uint256)" "$PAYMENTS_ESCROW" "$AMOUNT" \
  --confirmations 0 > /dev/null 2>&1
cast send --rpc-url "$RPC" --private-key "$PAYER_SECRET" \
  "$PAYMENTS_ESCROW" "deposit(address,address,uint256)" "$RECURRING_COLLECTOR" "$INDEXER" "$AMOUNT" \
  --confirmations 0 > /dev/null 2>&1
BAL=$(cast call --rpc-url "$RPC" "$PAYMENTS_ESCROW" "getBalance(address,address,address)(uint256)" "$PAYER" "$RECURRING_COLLECTOR" "$INDEXER" 2>/dev/null)
echo "Escrow balance: $BAL"

# ── Step 2: Authorize signer ─────────────────────────────────────────
echo "--- Step 2: Authorize signer ---"
IS_AUTH=$(cast call --rpc-url "$RPC" "$RECURRING_COLLECTOR" "isAuthorized(address,address)(bool)" "$PAYER" "$PAYER" 2>/dev/null || echo "false")
if [ "$IS_AUTH" != "true" ]; then
  CHAIN_ID=$(cast chain-id --rpc-url "$RPC")
  AUTH_DL=$(($(cast block latest --rpc-url "$RPC" --json | jq -r '.timestamp' | xargs printf "%d") + 86400))
  PACKED=$(cast abi-encode --packed "f(uint256,address,string,uint256,address)" "$CHAIN_ID" "$RECURRING_COLLECTOR" "authorizeSignerProof" "$AUTH_DL" "$PAYER")
  HASH=$(cast keccak "$PACKED")
  PROOF=$(cast wallet sign --private-key "$PAYER_SECRET" "$HASH")
  cast send --rpc-url "$RPC" --private-key "$PAYER_SECRET" \
    "$RECURRING_COLLECTOR" "authorizeSigner(address,uint256,bytes)" "$PAYER" "$AUTH_DL" "$PROOF" \
    --confirmations 0 > /dev/null 2>&1
fi
echo "Authorized: $(cast call --rpc-url "$RPC" "$RECURRING_COLLECTOR" "isAuthorized(address,address)(bool)" "$PAYER" "$PAYER")"

# ── Step 3: Accept agreement ─────────────────────────────────────────
echo "--- Step 3: Accept agreement ---"
CHAIN_TS=$(cast block latest --rpc-url "$RPC" --json | jq -r '.timestamp' | xargs printf "%d")
DEADLINE=$((CHAIN_TS + 7200))
ENDS_AT=$((CHAIN_TS + 604800))
NONCE=$(date +%s%N)

TERMS=$(cast abi-encode "f((uint256,uint256))" "(50,10)")
METADATA=$(cast abi-encode "f((bytes32,uint8,bytes))" "($DEPLOY_BYTES32,0,$TERMS)")

# Query EIP-712 domain
DOMAIN=$(cast call --rpc-url "$RPC" "$RECURRING_COLLECTOR" "eip712Domain()(bytes1,string,string,uint256,address,bytes32,uint256[])")
D_NAME=$(echo "$DOMAIN" | sed -n '2p' | tr -d '"')
D_VER=$(echo "$DOMAIN" | sed -n '3p' | tr -d '"')
D_CHAIN=$(echo "$DOMAIN" | sed -n '4p')
D_ADDR=$(echo "$DOMAIN" | sed -n '5p')
echo "Domain: name=$D_NAME version=$D_VER chainId=$D_CHAIN"

TYPED_DATA=$(mktemp /tmp/rca-XXXXXX.json)
cat > "$TYPED_DATA" <<EOFJSON
{
  "types": {
    "EIP712Domain": [
      {"name":"name","type":"string"},{"name":"version","type":"string"},
      {"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}
    ],
    "RecurringCollectionAgreement": [
      {"name":"deadline","type":"uint64"},{"name":"endsAt","type":"uint64"},
      {"name":"payer","type":"address"},{"name":"dataService","type":"address"},
      {"name":"serviceProvider","type":"address"},{"name":"maxInitialTokens","type":"uint256"},
      {"name":"maxOngoingTokensPerSecond","type":"uint256"},
      {"name":"minSecondsPerCollection","type":"uint32"},{"name":"maxSecondsPerCollection","type":"uint32"},
      {"name":"nonce","type":"uint256"},{"name":"metadata","type":"bytes"}
    ]
  },
  "primaryType":"RecurringCollectionAgreement",
  "domain":{"name":"$D_NAME","version":"$D_VER","chainId":$D_CHAIN,"verifyingContract":"$D_ADDR"},
  "message":{
    "deadline":$DEADLINE,"endsAt":$ENDS_AT,
    "payer":"$PAYER","dataService":"$SUBGRAPH_SERVICE","serviceProvider":"$INDEXER",
    "maxInitialTokens":"10000","maxOngoingTokensPerSecond":"100",
    "minSecondsPerCollection":3600,"maxSecondsPerCollection":86400,
    "nonce":"$NONCE","metadata":"$METADATA"
  }
}
EOFJSON

SIG=$(cast wallet sign --data --from-file --private-key "$PAYER_SECRET" "$TYPED_DATA")
rm -f "$TYPED_DATA"

ACCEPT_SIG="acceptIndexingAgreement(address,((uint64,uint64,address,address,address,uint256,uint256,uint32,uint32,uint256,bytes),bytes))"
echo "Calling acceptIndexingAgreement..."
cast send --rpc-url "$RPC" --private-key "$INDEXER_SECRET" \
  "$SUBGRAPH_SERVICE" "$ACCEPT_SIG" \
  "$ALLOC_ID" \
  "(($DEADLINE,$ENDS_AT,$PAYER,$SUBGRAPH_SERVICE,$INDEXER,10000,100,3600,86400,$NONCE,$METADATA),$SIG)" \
  --confirmations 0 2>&1 | grep -E 'status|Error|blockNumber'

# Get agreement ID
AGREEMENT_ID=$(cast call --rpc-url "$RPC" "$RECURRING_COLLECTOR" \
  "generateAgreementId(address,address,address,uint64,uint256)(bytes16)" \
  "$PAYER" "$SUBGRAPH_SERVICE" "$INDEXER" "$DEADLINE" "$NONCE")
echo "Agreement ID: $AGREEMENT_ID"

# Check lastCollectionAt
LAST_COL=$(cast call --rpc-url "$RPC" "$RECURRING_COLLECTOR" \
  "getAgreement(bytes16)(address,address,address,uint64,uint64,uint64,uint256,uint256,uint32,uint32,uint32,uint64,uint8)" \
  "$AGREEMENT_ID" | sed -n '5p')
echo "lastCollectionAt after accept: $LAST_COL"

# ── Step 4: Advance time ─────────────────────────────────────────────
echo ""
echo "--- Step 4: Advance time by 45100s ---"
# Incremental advances (7000s steps) to stay within maxPOIStaleness (7200s)
for chunk in 7000 7000 7000 7000 7000 7000 3100; do
  curl -sf "$RPC" -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"evm_increaseTime\",\"params\":[$chunk],\"id\":1}" > /dev/null
  cast rpc --rpc-url="$RPC" evm_mine > /dev/null
done
# Mine 10 extra blocks so agent's blockNumber-10 lands after the time jump
for _i in $(seq 1 10); do cast rpc --rpc-url="$RPC" evm_mine > /dev/null; done
echo "Time advanced. Current block: $(cast block-number --rpc-url "$RPC")"

NEW_TS=$(cast block latest --rpc-url "$RPC" --json | jq -r '.timestamp' | xargs printf "%d")
echo "New chain timestamp: $NEW_TS"
echo "Elapsed since accept: $((NEW_TS - CHAIN_TS))s"

# ── Step 5: Call collect directly ─────────────────────────────────────
echo ""
echo "--- Step 5: Call SubgraphService.collect ---"

BLOCK=$(cast block-number --rpc-url "$RPC")
RECENT_BLOCK=$((BLOCK - 10))
echo "Using recentBlock=$RECENT_BLOCK (current=$BLOCK, same as agent's blockNumber-10)"

# Get entity count from graph-node (same as agent)
GRAPH_NODE_STATUS="http://${GRAPH_NODE_HOST:-localhost}:${GRAPH_NODE_STATUS_PORT:-8030}/graphql"
ENTITIES=$(curl -s "$GRAPH_NODE_STATUS" -H 'content-type: application/json' \
  -d "{\"query\":\"{ indexingStatuses(subgraphs: [\\\"$DEPLOY_IPFS\\\"]) { entityCount } }\"}" \
  | jq -r '.data.indexingStatuses[0].entityCount // "0"')
echo "Entities from graph-node: $ENTITIES"

# Get POI from graph-node (same as agent)
BLOCK_HASH=$(cast block --rpc-url "$RPC" "$RECENT_BLOCK" --json | jq -r '.hash')
echo "Block hash for $RECENT_BLOCK: $BLOCK_HASH"
POI=$(curl -s "$GRAPH_NODE_STATUS" -H 'content-type: application/json' \
  -d "{\"query\":\"{ proofOfIndexing(subgraph: \\\"$DEPLOY_IPFS\\\", blockNumber: $RECENT_BLOCK, blockHash: \\\"$BLOCK_HASH\\\", indexer: \\\"$INDEXER\\\") }\"}" \
  | jq -r '.data.proofOfIndexing // "0x0000000000000000000000000000000000000000000000000000000000000000"')
echo "POI: $POI"

# Encode CollectIndexingFeeDataV1: (uint256 entities, bytes32 poi, uint256 poiBlock, bytes metadata, uint256 maxSlippage)
COLLECT_DATA=$(cast abi-encode "f(uint256,bytes32,uint256,bytes,uint256)" "$ENTITIES" "$POI" "$RECENT_BLOCK" "0x" 0)
echo "collectData (${#COLLECT_DATA} chars): ${COLLECT_DATA:0:40}..."

# Encode outer: (bytes16 agreementId, bytes collectData)
OUTER_DATA=$(cast abi-encode "f(bytes16,bytes)" "$AGREEMENT_ID" "$COLLECT_DATA")
echo "outerData (${#OUTER_DATA} chars): ${OUTER_DATA:0:40}..."

# PaymentTypes: QueryFee=0, IndexingFee=1, IndexingRewards=2
echo ""
echo "Calling collect(indexer, IndexingFee=1, data)..."
cast send --rpc-url "$RPC" --private-key "$INDEXER_SECRET" \
  "$SUBGRAPH_SERVICE" \
  "collect(address,uint8,bytes)" \
  "$INDEXER" 1 "$OUTER_DATA" \
  2>&1 | grep -E 'status|Error|custom error|blockNumber|hash'

echo ""
echo "--- Step 5b: Check lastCollectionAt after collect ---"
NEW_LAST_COL=$(cast call --rpc-url "$RPC" "$RECURRING_COLLECTOR" \
  "getAgreement(bytes16)(address,address,address,uint64,uint64,uint64,uint256,uint256,uint32,uint32,uint32,uint64,uint8)" \
  "$AGREEMENT_ID" | sed -n '5p')
echo "lastCollectionAt: $NEW_LAST_COL (was: $LAST_COL)"

if [ "$NEW_LAST_COL" != "$LAST_COL" ] && [ -n "$NEW_LAST_COL" ] && [ "$NEW_LAST_COL" != "0" ]; then
  echo "SUCCESS: Collection updated lastCollectionAt!"
else
  echo "FAILED: lastCollectionAt unchanged"
  echo ""
  echo "--- Debug: trying estimate to see error ---"
  cast estimate --rpc-url "$RPC" --from "$INDEXER" \
    "$SUBGRAPH_SERVICE" "collect(address,uint8,bytes)" \
    "$INDEXER" 1 "$OUTER_DATA" 2>&1 || true

  echo ""
  echo "--- Debug: trace call ---"
  CALLDATA=$(cast calldata "collect(address,uint8,bytes)" "$INDEXER" 1 "$OUTER_DATA")
  cast rpc --rpc-url "$RPC" debug_traceCall \
    "{\"from\":\"$INDEXER\",\"to\":\"$SUBGRAPH_SERVICE\",\"data\":\"$CALLDATA\"}" \
    "latest" \
    "{\"tracer\":\"callTracer\",\"tracerConfig\":{\"onlyTopCall\":false}}" 2>&1 | python3 -c "
import sys,json
def show(c, d=0):
    p='  '*d; to=c.get('to','?')[:20]; err=c.get('error','')
    out=c.get('output','')[:120]; gas=int(c.get('gasUsed','0x0'),16)
    typ=c.get('type','')
    print(f'{p}{typ}->{to}... gas={gas} err={err}')
    if out and err: print(f'{p}  output={out}')
    for s in c.get('calls',[]): show(s,d+1)
r=json.load(sys.stdin); show(r.get('result',r))
" 2>/dev/null || echo "(trace failed)"
fi

echo ""
echo "=== Done ==="
