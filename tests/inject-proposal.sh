#!/bin/bash
# Inject a pending_rca_proposals row into the indexer DB (bypasses dipper/indexer-service).
# Usage: inject-proposal.sh <deployment_ipfs_hash> [--deadline <sec>] [--nonce <n>] [--status pending] [--post-offer] [--no-row]
#   --post-offer : also post the on-chain Offer via RAM.offerAgreement (DIPPER_SECRET, AGREEMENT_MANAGER_ROLE)
#   --no-row     : only post the offer, do not insert the DB row
# Encodes a SignedRCA (empty sig) matching what dipper produces.
set -u
cd "$(dirname "$0")/.."
# Indexer source (for ethers + toolshed). Reuse the dev-override var; read from env or .env.local.
INDEXER_SRC="${INDEXER_SRC:-${INDEXER_AGENT_SOURCE_ROOT:-$(grep -m1 '^INDEXER_AGENT_SOURCE_ROOT=' .env.local 2>/dev/null | cut -d= -f2-)}}"
[ -z "$INDEXER_SRC" ] && { echo "ERROR: set INDEXER_AGENT_SOURCE_ROOT (your indexer main-dips checkout) in .env.local, or export INDEXER_SRC"; exit 1; }
GQL=http://localhost:8000
DEP_IPFS="$1"; shift
STATUS=pending
POST_OFFER=no
INSERT_ROW=yes
PASS_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --status) STATUS="$2"; shift 2 ;;
    --post-offer) POST_OFFER=yes; shift ;;
    --no-row) INSERT_ROW=no; shift ;;
    *) PASS_ARGS+=("$1" "$2"); shift 2 ;;
  esac
done

# Resolve the deployment bytes32 from the network subgraph.
B32=$(curl -s -m8 "$GQL/subgraphs/name/graph-network" -H 'content-type: application/json' \
  -d "{\"query\":\"{ subgraphDeployments(where:{ipfsHash:\\\"$DEP_IPFS\\\"}){ id } }\"}" | jq -r '.data.subgraphDeployments[0].id // empty')
[ -z "$B32" ] && { echo "ERROR: could not resolve bytes32 for $DEP_IPFS (published on GNS?)"; exit 1; }

OUT=$(NODE_PATH="$INDEXER_SRC/node_modules" node tests/inject-rca.cjs --deployment-bytes32 "$B32" "${PASS_ARGS[@]}")
[ $? -ne 0 ] && { echo "ERROR: encode failed"; echo "$OUT"; exit 1; }
HEX=$(echo "$OUT" | jq -r '.payloadHex' | sed 's/^0x//')
OFFERDATA=$(echo "$OUT" | jq -r '.offerDataHex')
DEADLINE=$(echo "$OUT" | jq -r '.agreementIdInputs.deadline')
NONCE=$(echo "$OUT" | jq -r '.agreementIdInputs.nonce')

RC=0x4A679253410272dd5232B3Ff7cF5dbB88f295319
SS=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
RAM=0x3347b4d90ebe72befb30444c9966b2b990ae9fcb
INDEXER=0xf4EF6650E48d099a4972ea5B414daB86e1998Bd3
DIPPER_SECRET=0x254aaacc1a4091fdb844b297b2c00db641bd3a613914e9afaa0dbfce5c5cab5a  # 0x85404..., AGREEMENT_MANAGER_ROLE

# Derive the agreement id on-chain (the value the agent uses to match the offer).
AGID=$(timeout 12 docker exec chain cast call --rpc-url http://localhost:8545 "$RC" \
  "generateAgreementId(address,address,address,uint64,uint256)(bytes16)" "$RAM" "$SS" "$INDEXER" "$DEADLINE" "$NONCE" 2>/dev/null)

# Optionally post the on-chain Offer via RAM.offerAgreement(collector, OFFER_TYPE_NEW=1, offerData).
if [ "$POST_OFFER" = "yes" ]; then
  R=$(timeout 30 docker exec chain cast send --rpc-url http://localhost:8545 --confirmations 0 --private-key "$DIPPER_SECRET" \
    "$RAM" "offerAgreement(address,uint8,bytes)" "$RC" 1 "$OFFERDATA" 2>&1 | grep -iE '^status|error|revert' | head -1)
  echo "  post-offer($AGID): $R"
fi

# Insert the row.
if [ "$INSERT_ROW" = "yes" ]; then
  docker exec postgres psql -U postgres -d indexer_components_1 -tAq \
    -c "INSERT INTO pending_rca_proposals (id, signed_payload, version, status, created_at, updated_at) VALUES (gen_random_uuid(), decode('$HEX','hex'), 2, '$STATUS', now(), now());" >/dev/null \
    && echo "injected: deployment=$DEP_IPFS nonce=$NONCE deadline=$DEADLINE agreementId=$AGID status=$STATUS" \
    || echo "ERROR: insert failed"
fi
