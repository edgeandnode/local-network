#!/bin/bash
# Make a Studio-published test subgraph queryable end-to-end on the local stack:
#   1. mint curation signal on the deployment (skipped if it already has signal)
#   2. set an 'always' indexing rule so the indexer allocates to it
#   3. if the indexer-agent's action queue is jammed on nonce drift, restart the
#      agent (the only reliable unblock today -- see BUGS BUG-022 family)
# Then poll for the active allocation and print the gateway _logs query to run.
#
# Local-only (Docker on this host, no VM/SSH). For a VM setup, wrap the docker
# compose / curl calls in `ssh lnet-test`.
#
# Usage: scripts/index-published-subgraph.sh <deployment-ipfs-hash> [agent-port] [signal-grt]
#   <deployment-ipfs-hash>  Qm... CID shown after publishing in Studio
#   [agent-port]            indexer-agent management port (default 7600 = primary)
#   [signal-grt]            curation signal to mint if none exists (default 1000)
set -euo pipefail

cd "$(dirname "$0")/.."
export DOCKER_DEFAULT_PLATFORM="${DOCKER_DEFAULT_PLATFORM:-}"

DEP_IPFS="${1:-}"
AGENT_PORT="${2:-7600}"
SIGNAL_GRT="${3:-1000}"
if [ -z "$DEP_IPFS" ]; then
  echo "Usage: $0 <deployment-ipfs-hash> [agent-port] [signal-grt]" >&2
  exit 1
fi

RPC=http://localhost:8545
GATEWAY=http://localhost:7700
NET_SG=http://localhost:8000/subgraphs/name/graph-network
AGENT="http://localhost:${AGENT_PORT}/"
# hardhat account 0 (deployer) holds ~10B GRT and is the curator here
SECRET=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
PROTO=eip155:1337
BEARER=deadbeefdeadbeefdeadbeefdeadbeef

gq()  { curl -s "$NET_SG" -H 'content-type: application/json' -d "$1"; }
amgr() { curl -s "$AGENT"  -H 'content-type: application/json' -d "$1"; }
jget() { python3 -c "import json,sys;$1"; }

# --- 1. contract addresses from horizon.json (no jq in graph-node image) ------
read_addr() {
  docker compose exec -T graph-node cat /opt/config/horizon.json \
    | jget "print(json.load(sys.stdin)['1337']['$1']['address'])"
}
GT=$(read_addr L2GraphToken)
CU=$(read_addr L2Curation)

# --- 2. resolve bytes32 id + sanity checks ------------------------------------
META=$(gq "{\"query\":\"{ subgraphDeployments(where:{ipfsHash:\\\"$DEP_IPFS\\\"}){ id signalAmount manifest{ network } } }\"}")
DEP_ID=$(echo "$META"  | jget "d=json.load(sys.stdin)['data']['subgraphDeployments'];print(d[0]['id'] if d else '')")
NETWORK=$(echo "$META" | jget "d=json.load(sys.stdin)['data']['subgraphDeployments'];print((d[0].get('manifest') or {}).get('network') or '' if d else '')")
SIGNAL=$(echo "$META"  | jget "d=json.load(sys.stdin)['data']['subgraphDeployments'];print(d[0]['signalAmount'] if d else '0')")

if [ -z "$DEP_ID" ]; then
  echo "ERROR: $DEP_IPFS not found in the network subgraph." >&2
  echo "       Publish it from the Studio UI first (this script does not publish)." >&2
  exit 1
fi
echo "deployment : $DEP_IPFS"
echo "  bytes32  : $DEP_ID"
echo "  network  : ${NETWORK:-<null>}"
echo "  signal   : $SIGNAL"

if [ -z "$NETWORK" ]; then
  echo "WARNING: manifest.network is null -> the gateway will drop this deployment" >&2
  echo "         ('no valid versions'). It was deployed with a JSON manifest; redeploy" >&2
  echo "         with the YAML-manifest deploy-studio-test-subgraphs.py. Continuing anyway" >&2
  echo "         (allocation/indexing will work; only gateway routing is blocked)." >&2
fi

# --- 3. curation signal (only if none) ----------------------------------------
if [ "$SIGNAL" = "0" ]; then
  SIG_WEI=$(python3 -c "print($SIGNAL_GRT * 10**18)")
  echo "--- minting ${SIGNAL_GRT} GRT curation signal ---"
  cast send --rpc-url="$RPC" --private-key="$SECRET" "$GT" "approve(address,uint256)" "$CU" "$SIG_WEI" >/dev/null
  cast send --rpc-url="$RPC" --private-key="$SECRET" "$CU" "mint(bytes32,uint256,uint256)" "$DEP_ID" "$SIG_WEI" "0" >/dev/null
  NOW=$(cast call --rpc-url="$RPC" "$CU" "getCurationPoolSignal(bytes32)(uint256)" "$DEP_ID" | awk '{print $1}')
  echo "  signal now: $NOW wei"
else
  echo "--- signal already present, skipping mint ---"
fi

# --- 4. 'always' indexing rule ------------------------------------------------
echo "--- setting 'always' indexing rule (agent :${AGENT_PORT}) ---"
amgr "{\"query\":\"mutation { setIndexingRule(rule: { identifier: \\\"$DEP_IPFS\\\", identifierType: deployment, decisionBasis: always, protocolNetwork: \\\"$PROTO\\\" }) { identifier decisionBasis } }\"}" >/dev/null
echo "  rule set (decisionBasis: always)"

# --- 5. poll for allocation; restart agent if the queue is jammed on nonce ----
active_allocs() {
  gq "{\"query\":\"{ subgraphDeployments(where:{ipfsHash:\\\"$DEP_IPFS\\\"}){ indexerAllocations(where:{status:Active}){ id } } }\"}" \
    | jget "d=json.load(sys.stdin)['data']['subgraphDeployments'];print(len(d[0]['indexerAllocations']) if d else 0)"
}
poll_alloc() {  # $1 = iterations (~14s each, plus a mined block)
  for _ in $(seq 1 "$1"); do
    ./scripts/mine-block.sh 3 >/dev/null 2>&1 || true
    [ "$(active_allocs)" -gt 0 ] && return 0
    sleep 14
  done
  return 1
}
queue_jammed() {  # approved actions stuck AND a failed action blames nonce
  local approved nonce
  approved=$(amgr "{\"query\":\"{ actions(filter:{protocolNetwork:\\\"$PROTO\\\",status:\\\"approved\\\"}){ id } }\"}" \
    | jget "print(len(json.load(sys.stdin)['data']['actions']))" 2>/dev/null || echo 0)
  nonce=$(amgr "{\"query\":\"{ actions(filter:{protocolNetwork:\\\"$PROTO\\\",status:\\\"failed\\\"}){ failureReason } }\"}" \
    | grep -c "nonce has already been used" || true)
  [ "${approved:-0}" -gt 0 ] && [ "${nonce:-0}" -gt 0 ]
}

echo "--- waiting for allocation (agent reconciles ~every 75s) ---"
if poll_alloc 10; then
  echo ">>> allocation active"
elif queue_jammed; then
  echo "--- action queue jammed on nonce drift; restarting indexer-agent ---"
  docker compose restart indexer-agent >/dev/null
  for _ in $(seq 1 30); do
    docker compose ps indexer-agent --format '{{.Status}}' | grep -q healthy && break
    sleep 4
  done
  if poll_alloc 14; then
    echo ">>> allocation active after restart"
  else
    echo "ERROR: still no allocation after restart. Inspect: docker compose logs indexer-agent" >&2
    exit 1
  fi
else
  echo "ERROR: no allocation and queue not obviously jammed." >&2
  echo "       Inspect rules/actions: docker compose logs indexer-agent" >&2
  exit 1
fi

# --- 6. report gateway routability + the query to run -------------------------
SID=$(gq "{\"query\":\"{ subgraphs(where:{active:true}){ id currentVersion{ subgraphDeployment{ ipfsHash } } } }\"}" \
  | jget "
import json,sys
for s in json.load(sys.stdin)['data']['subgraphs']:
    cv=s.get('currentVersion') or {}
    if (cv.get('subgraphDeployment') or {}).get('ipfsHash')=='$DEP_IPFS': print(s['id']); break")

echo ""
echo "=== DONE: $DEP_IPFS is allocated and indexing ==="
if [ -n "${NETWORK:-}" ] && [ -n "$SID" ]; then
  echo "gateway subgraph id: $SID"
  echo "query _logs through the gateway:"
  echo "  curl -s \"$GATEWAY/api/subgraphs/id/$SID\" \\"
  echo "    -H 'content-type: application/json' \\"
  echo "    -H 'Authorization: Bearer $BEARER' \\"
  echo "    -d '{\"query\":\"{ _logs(first:5){ timestamp level text meta { module line } } }\"}'"
elif [ -z "${NETWORK:-}" ]; then
  echo "NOTE: manifest.network is null -> not gateway-routable. Query _logs directly on graph-node:"
  echo "  curl -s \"http://localhost:8000/subgraphs/id/$DEP_IPFS\" \\"
  echo "    -H 'content-type: application/json' \\"
  echo "    -d '{\"query\":\"{ _logs(first:5){ timestamp level text } }\"}'"
fi
