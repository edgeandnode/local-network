#!/bin/bash
# DIPs end-to-end regression: Phase 0 fixtures + D-1..D-8.
# Assumes a fresh, healthy stack (agent from main-dips source via dev override).
set -u
cd "$(dirname "$0")/.."

RPC=http://localhost:8545
GQL=http://localhost:8000
STATUS=http://localhost:8030/graphql
MGMT=http://localhost:7600
DRPC=http://localhost:9000
CLI_IMG=ghcr.io/edgeandnode/dipper-cli:sha-cb89726
RECEIVER_KEY=0x2ee789a68207020b45607f5adb71933de0946baebbaaab74af7cbd69c8a90573
SAO_KEY=0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
BEARER=deadbeefdeadbeefdeadbeefdeadbeef
# deterministic hardhat addresses
SS=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
RC=0x4A679253410272dd5232B3Ff7cF5dbB88f295319
ESCROW=0x322813Fd9A801c5507c9de605d63CEA4f2CE6c44
RM=0xa82fF9aFd8f496c3d6ac40E2a0F282E47488CFc9
EM=0x7a2088a1bFc9d81c55368AE168C2C02570cB814F
RAM=0x3347b4d90ebe72befb30444c9966b2b990ae9fcb
INDEXER=0xf4EF6650E48d099a4972ea5B414daB86e1998Bd3
ZP=0x0000000000000000000000000000000000000000000000000000000000000000
# deterministic deployment ids (same subgraph content each deploy)
T_PRIMARY=QmNePZ64EJ8LZSBSmrw2xtPF8kdYVtfDu7849t8r5wgmyA
T_REUSE=QmcbVhNwLfuXnowqwRkJmLsEhWSoJKrGnzdQtxWbnF3tMy
T_DENIED=QmTBepkzkmSFuQmSEvRMTXW8QkDPLxhiTy8egfJgaC5rV7
T_A=QmTo7BjJzXQMcTrKtWzFEkeo7ztuRKC1b23MLtqj1xBUKo
T_B=QmeQtqvVMcWeBj7Sy5nvfUUu9DkQms12WZKj7V3hRb3trj

P=0; F=0
pass(){ echo "  PASS: $1"; P=$((P+1)); }
fail(){ echo "  FAIL: $1"; F=$((F+1)); }
gql(){ curl -s -m8 "$1" -H 'content-type: application/json' -d "$2" 2>/dev/null; }
agstate(){ timeout 15 docker exec chain cast call --rpc-url $RPC "$RC" "getAgreement(bytes16)(address,uint64,uint32,address,uint64,uint32,address,uint64,uint32,uint256,uint256,bytes32,uint64,uint16,uint8)" "$1" 2>/dev/null | tail -1; }
colinfo(){ timeout 12 docker exec chain cast call --rpc-url $RPC "$RC" "getCollectionInfo(bytes16)(bool,uint256,uint8)" "$1" 2>/dev/null; }
allocof(){ gql "$GQL/subgraphs/name/graph-network" "{\"query\":\"{ allocations(where:{status:Active, subgraphDeployment_:{ipfsHash:\\\"$1\\\"}}){ id } }\"}" | jq -r '.data.allocations[0].id // "none"'; }
allocstatus(){ gql "$GQL/subgraphs/name/graph-network" "{\"query\":\"{ allocations(where:{id:\\\"$1\\\"}){ status } }\"}" | jq -r '.data.allocations[0].status // "none"'; }
dstat(){ docker exec postgres psql -U postgres -d dipper_1 -tAq -c "SELECT status FROM dipper_reg_indexing_agreements WHERE deployment_id='$1' ORDER BY updated_at DESC LIMIT 1;" 2>/dev/null; }
agid(){ gql "$GQL/subgraphs/name/indexing-payments" "{\"query\":\"{ indexingAgreements(where:{allocationId:\\\"$1\\\"}){ id } }\"}" | jq -r '.data.indexingAgreements[0].id // empty'; }
lca(){ gql "$GQL/subgraphs/name/indexing-payments" "{\"query\":\"{ indexingAgreements(where:{allocationId:\\\"$1\\\"}){ lastCollectionAt } }\"}" | jq -r '.data.indexingAgreements[0].lastCollectionAt // "0"'; }
# cast returns the tuple on ONE line: (addr, bytes32, TOKENS [..], ...) — take the 3rd comma field, first token
tokens(){ timeout 12 docker exec chain cast call --rpc-url $RPC "$SS" "getAllocation(address)((address,bytes32,uint256,uint256,uint256,uint256,uint256,uint256))" "$1" 2>/dev/null | sed 's/[()]//g' | awk -F', ' '{print $3}' | awk '{print $1}'; }
originate(){ docker run --rm --network host $CLI_IMG indexings set-target-candidates --server-url $DRPC --signing-key $RECEIVER_KEY "$1" 1337 --num-candidates "${2:-1}" 2>&1 | tail -1; }
setrule(){ python3 - "$1" "$2" <<'PY' | curl -s -m8 "http://localhost:7600" -H 'content-type: application/json' --data @- >/dev/null
import json,sys
print(json.dumps({"query":"mutation S($r:IndexingRuleInput!){setIndexingRule(rule:$r){identifier}}","variables":{"r":{"identifier":sys.argv[1],"identifierType":"deployment","protocolNetwork":"eip155:1337","decisionBasis":sys.argv[2]}}}))
PY
}
mine(){ timeout 10 docker exec chain cast rpc --rpc-url $RPC anvil_mine 0x1 "${1:-0x78}" >/dev/null 2>&1; }
wait_accept(){ for i in $(seq 1 25); do [ "$(dstat "$1")" = "6" ] && [ "$(allocof "$1")" != "none" ] && { allocof "$1"; return; }; sleep 6; done; echo none; }
bytes32of(){ gql "$GQL/subgraphs/name/graph-network" "{\"query\":\"{ subgraphDeployments(where:{ipfsHash:\\\"$1\\\"}){ id } }\"}" | jq -r '.data.subgraphDeployments[0].id'; }

echo "############ Phase 0: fixtures ############"
python3 scripts/deploy-test-subgraph.py 6 dips >/dev/null 2>&1 && echo "  published 6 subgraphs" || echo "  publish failed"
setrule "$T_REUSE" always
echo "  set always on T-reuse; waiting for its allocation..."
RA=none; for i in $(seq 1 24); do RA=$(allocof "$T_REUSE"); [ "$RA" != "none" ] && break; sleep 10; done
[ "$RA" != "none" ] && pass "Phase0: T-reuse pre-allocated ($RA)" || fail "Phase0: T-reuse not allocated"
# seed IISA
for i in $(seq 1 40); do curl -s -m6 "http://localhost:7700/api/deployments/id/QmU9fn4xn2WZ2xTBwUswyqxQqt7DmbLTQhm5dQ5sMfXxur" -H 'content-type: application/json' -H "Authorization: Bearer $BEARER" -d '{"query":"{ _meta{block{number}} }"}' >/dev/null; done
echo "  sent gateway queries; running IISA scoring..."
SC=$(docker compose --env-file .env --env-file .env.local run --rm iisa-cronjob 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g' | grep -oE 'indexers=[0-9]+' | tail -1)
[ "$SC" = "indexers=1" ] && pass "Phase0: IISA scored ($SC)" || fail "Phase0: IISA scoring ($SC)"

echo "############ D-2/D-3.2: originate + accept (new allocation) ############"
originate "$T_A" >/dev/null; AA=$(wait_accept "$T_A")
[ "$AA" != "none" ] && pass "D-2/D-3.2: T-A accepted, new alloc $AA" || fail "D-2/D-3.2: T-A not accepted"
[ "$(dstat "$T_A")" = "6" ] && pass "D-2.2: dipper AcceptedOnChain" || fail "D-2.2: dipper not 6"
AGA=$(agid "$AA"); [ -n "$AGA" ] && [ "$(gql "$GQL/subgraphs/name/indexing-payments" "{\"query\":\"{ offer(id:\\\"$AGA\\\"){ id } }\"}" | jq -r '.data.offer.id // empty')" = "$AGA" ] && pass "D-2.3: Offer indexed" || fail "D-2.3: Offer missing"
[ "$(agstate "$AGA")" = "1" ] && pass "D-3.2: on-chain agreement Accepted(1)" || fail "D-3.2: agreement not 1"
[ "$(gql "$MGMT" '{"query":"{ indexingRules(merged:false){ identifier decisionBasis } }"}' | jq -r ".data.indexingRules[]|select(.identifier==\"$T_A\").decisionBasis")" = "dips" ] && pass "D-3.2: dips rule created" || fail "D-3.2: no dips rule"

echo "############ D-3.1: accept reusing existing allocation ############"
RUALLOC=$(allocof "$T_REUSE")
originate "$T_REUSE" >/dev/null; wait_accept "$T_REUSE" >/dev/null
[ "$(dstat "$T_REUSE")" = "6" ] && pass "D-3.1: T-reuse AcceptedOnChain" || fail "D-3.1: T-reuse not 6"
[ "$(allocof "$T_REUSE")" = "$RUALLOC" ] && pass "D-3.1: allocation reused ($RUALLOC)" || fail "D-3.1: allocation changed"

echo "############ D-4: sizing ############"
[ "$(tokens "$AA")" = "10000000000000000" ] && pass "D-4.1: reward sizing 0.01 GRT" || fail "D-4.1: tokens=$(tokens "$AA")"
B32=$(bytes32of "$T_DENIED")
timeout 20 docker exec chain cast send --rpc-url $RPC --confirmations 0 --private-key $SAO_KEY "$RM" "setDenied(bytes32,bool)" "$B32" true >/dev/null 2>&1
[ "$(timeout 10 docker exec chain cast call --rpc-url $RPC "$RM" "isDenied(bytes32)(bool)" "$B32" 2>/dev/null)" = "true" ] && echo "  denied T-denied" || echo "  deny failed"
originate "$T_DENIED" >/dev/null; DA=$(wait_accept "$T_DENIED")
[ "$DA" != "none" ] && [ "$(tokens "$DA")" = "1000000000000000000" ] && pass "D-4.2: denied sizing 1 GRT" || fail "D-4.2: denied tokens=$(tokens "$DA")"
timeout 20 docker exec chain cast send --rpc-url $RPC --confirmations 0 --private-key $SAO_KEY "$RM" "setDenied(bytes32,bool)" "$B32" false >/dev/null 2>&1
echo "  undenied T-denied"

echo "############ D-5: indexing & reconciliation ############"
[ "$(gql "$STATUS" "{\"query\":\"{ indexingStatuses(subgraphs:[\\\"$T_A\\\"]){ synced health } }\"}" | jq -r '.data.indexingStatuses[0].health')" = "healthy" ] && pass "D-5.1: deployment healthy" || fail "D-5.1: not healthy"
[ "$(gql "$GQL/subgraphs/name/indexing-payments" "{\"query\":\"{ indexingAgreements(where:{allocationId:\\\"$AA\\\"}){ state } }\"}" | jq -r '.data.indexingAgreements[0].state')" = "Accepted" ] && pass "D-5.2: agreement Accepted on subgraph" || fail "D-5.2: not Accepted"
RULE1=$(gql "$MGMT" '{"query":"{ indexingRules(merged:false){ identifier decisionBasis } }"}' | jq -r ".data.indexingRules[]|select(.identifier==\"$T_A\").decisionBasis")
sleep 35
RULE2=$(gql "$MGMT" '{"query":"{ indexingRules(merged:false){ identifier decisionBasis } }"}' | jq -r ".data.indexingRules[]|select(.identifier==\"$T_A\").decisionBasis")
[ "$RULE1" = "dips" ] && [ "$RULE2" = "dips" ] && [ "$(allocstatus "$AA")" = "Active" ] && pass "D-5.3: dips rule persists + alloc not auto-closed" || fail "D-5.3: rule/alloc changed ($RULE1->$RULE2, $(allocstatus "$AA"))"

echo "############ D-6: recurring collection ############"
declare -a LCAS ENTS
for w in 1 2 3; do
  pre=$(lca "$AA"); mine 0x78
  for _ in $(seq 1 8); do sleep 5; [ "$(lca "$AA")" != "$pre" ] && break; done
done
# read last 6 collections for entity scaling
COLS=$(gql "$GQL/subgraphs/name/indexing-payments" "{\"query\":\"{ indexingFeeCollections(where:{agreement:\\\"$AGA\\\"}, orderBy:blockTimestamp, orderDirection:asc, first:30){ tokensCollected entities } }\"}")
NCOL=$(echo "$COLS" | jq '.data.indexingFeeCollections | length')
[ "$NCOL" -ge 2 ] && pass "D-6.2: recurring collection ($NCOL collections across windows)" || fail "D-6.2: only $NCOL collections"
# entity scaling: entities monotonic up and tokens generally increase over the steady baseline
MONO=$(echo "$COLS" | jq '[.data.indexingFeeCollections[].entities|tonumber] | (. == (sort))')
[ "$MONO" = "true" ] && pass "D-6.5: entities monotonic (payout scales)" || fail "D-6.5: entities not monotonic"

echo "############ D-7: protection ############"
NET=local-network_default; SI=local-network-start-indexing
GI023=/usr/local/lib/node_modules/@graphprotocol/indexer-cli/bin/graph-indexer
# D-7.1 non-forced close rejected
R71=$(docker run --rm --network "$NET" --entrypoint sh "$SI" -c "$GI023 indexer connect http://indexer-agent:7600 >/dev/null 2>&1; $GI023 indexer allocations close hardhat $AA $ZP --network hardhat 2>&1" 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g')
echo "$R71" | grep -qi 'DIPS agreement that can still collect' && pass "D-7.1: non-forced close rejected" || fail "D-7.1: not rejected"
[ "$(allocstatus "$AA")" = "Active" ] && pass "D-7.2: allocation still Active (not auto-closed)" || fail "D-7.2: alloc not Active"
# D-7.3 force close via 0.25.10 CLI (agent container)
EB=$(timeout 10 docker exec chain cast call --rpc-url $RPC "$EM" 'currentEpochBlock()(uint256)' 2>/dev/null | awk '{print $1}')
docker exec indexer-agent sh -c "cd /opt/indexer-agent-source-root && node packages/indexer-cli/bin/graph-indexer indexer connect http://localhost:7600 >/dev/null 2>&1 && node packages/indexer-cli/bin/graph-indexer indexer allocations close $AA $ZP $EB $ZP --network hardhat --force >/dev/null 2>&1"
sleep 6
[ "$(agstate "$AGA")" = "2" ] && [ "$(allocstatus "$AA")" = "Closed" ] && pass "D-7.3: force-close -> agreement Canceled(2) + alloc Closed" || fail "D-7.3: state=$(agstate "$AGA") alloc=$(allocstatus "$AA")"

echo "############ D-8: cancellation ############"
# D-8.1 payer cancel on T-B
originate "$T_B" >/dev/null; BA=$(wait_accept "$T_B"); AGB=$(agid "$BA")
originate "$T_B" 0 >/dev/null
S3=no; for i in $(seq 1 12); do [ "$(agstate "$AGB")" = "3" ] && { S3=yes; break; }; sleep 6; done
[ "$S3" = "yes" ] && pass "D-8.1: payer cancel -> CanceledByPayer(3)" || fail "D-8.1: state=$(agstate "$AGB")"
preB=$(lca "$BA"); mine 0x78; for _ in $(seq 1 8); do sleep 5; [ "$(lca "$BA")" != "$preB" ] && break; done
[ "$(lca "$BA")" != "$preB" ] && pass "D-8.1: final collection after cancel" || fail "D-8.1: no final collection"
# D-8.2 protection releases -> allocation closes
CL=no; for i in $(seq 1 20); do [ "$(allocstatus "$BA")" = "Closed" ] && { CL=yes; break; }; mine 0x78; sleep 8; done
[ "$CL" = "yes" ] && pass "D-8.2: protection releases -> alloc Closed" || fail "D-8.2: alloc=$(allocstatus "$BA")"
# D-8.3 indexer opt-out (never) on a fresh agreement (reuse T-A deployment now that it's free? use T_PRIMARY)
originate "$T_PRIMARY" >/dev/null; PA=$(wait_accept "$T_PRIMARY"); AGP=$(agid "$PA")
setrule "$T_PRIMARY" never
S2=no; for i in $(seq 1 20); do [ "$(agstate "$AGP")" = "2" ] && [ "$(allocstatus "$PA")" = "Closed" ] && { S2=yes; break; }; sleep 8; done
[ "$S2" = "yes" ] && pass "D-8.3: opt-out -> SP cancel(2) + alloc Closed" || fail "D-8.3: state=$(agstate "$AGP") alloc=$(allocstatus "$PA")"

echo "############ RESULT ############"
echo "PASS=$P FAIL=$F"
