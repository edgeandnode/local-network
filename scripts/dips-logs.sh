#!/bin/sh
# Merge + ANSI-strip + pre-filter every DIPs container into ONE plain-text stream so Dozzle (whose
# search is per-container and breaks on color codes) shows them as one. A 10s rescan auto-attaches new
# containers, so /add-indexers extras appear without a restart; reattach loop recovers /fresh-deploy.

# Deploy: copy to the VM at /home/mainuser/dips-logs.sh -- outside the repo clone, so it survives
# /fresh-deploy -- then run a standalone container that tails the others via the docker socket.
# After editing, re-copy to the VM and `docker restart dips-logs` (NOISE/MATCH read once at start).

# docker run -d --name dips-logs --restart always \
#   -v /home/mainuser/dips-logs.sh:/dips-logs.sh -v /var/run/docker.sock:/var/run/docker.sock \
#   docker:cli sh /dips-logs.sh

MATCH='^(dipper|iisa|indexer-agent|indexer-service|graph-node)(-[0-9]+)?$'
ESC=$(printf '\033')

# Idle-noise + non-DIPs chatter, matched after ANSI strip. Goal: idle near-silent, lights up on real DIPs
# events. Drops graph-node per-block/epoch-decode/pruning, service spans+query-fee, dipper heartbeats,
# health-checks, agent reconciliation plumbing. Keeps escrow/topology, tx, POI/reward collection; dedupes heartbeats.
NOISE='Start processing block|Committed write batch|triggers: 0,|entities: 0,|Syncing [0-9]+ blocks from Ethereum|data_source: DataEdge|Start pruning|Finished pruning|Found [0-9]+ triggers|Applying [0-9]+ entity'
NOISE="$NOISE|uri: /status|router::http_request|routes::status|at crates/|tap_receipt|auth::tap|value_check|request_handler|pagination complete"
NOISE="$NOISE|Accepting new connection|starting new connection|starting expiration scan|no expired agreements|paginated_client"
NOISE="$NOISE|GET /health|\"msg\":\"GET / 200|\"level\":10,|No pending RAVs"
NOISE="$NOISE|Identify expiring allocations|Expired allocations found"
NOISE="$NOISE|0 pending, 0 active accepted|No collectable agreements found|No recently closed allocations|No deployment changes are necessary"
NOISE="$NOISE|[Rr]econcil|Fetch subgraph deployment assignments|Fetching mapped subgraph deployment|Fetching active deployments|Refresh eligible allocations|Fetch recently closed allocations|isPaused|Execute 'actions' query|Ensuring indexing rules for DIPs|Fetching indexing rules|Fetch Active allocations|Query subgraph deployments|Finished fetching "

# Dedupe-on-change for unchanging state heartbeats (escrow / allocations / balance / chain / DIPs rules / collection):
# strip the volatile parts (timestamps, block numbers, poll counters) to a value key, then suppress a line
# only when that value matches the last one printed. First sighting prints; changes reprint; errors pass.
tail_one() {
  c="$1"
  gap_announced=0
  while true; do
    # Skip-and-announce-once while the container is absent (stopped, recreated, or removed) so a
    # permanently-gone container doesn't reprint every loop; reattach silently once it is back.
    if ! docker ps --format '{{.Names}}' | grep -qx "$c"; then
      [ "$gap_announced" = 0 ] && echo "[dips-logs] $c not running; will reattach when it returns"
      gap_announced=1; sleep 2; continue
    fi
    gap_announced=0
    docker logs -f --tail 0 "$c" 2>&1 | awk -v c="$c" -v noise="$NOISE" -v esc="$ESC" '
      { clean = $0; gsub(esc "\\[[0-9;]*m", "", clean) }
      clean ~ /^[[:space:]]*$/ { next }
      noise != "" && clean ~ noise { next }
      {
        tag = ""
        if (clean ~ /escrow accounts loaded/) tag = "escrow"
        else if (clean ~ /returned allocations/) tag = "alloc"
        else if (clean ~ /Current operator ETH balance/) tag = "eth"
        else if (clean ~ /chain listener heartbeat/) tag = "chain"
        else if (clean ~ /Ensuring DIPS indexing rules/) tag = "dips"
        else if (clean ~ /No agreements ready for collection/) tag = "collect"
        if (tag != "") {
          v = clean
          gsub(/[0-9-]+T[0-9:.]+Z/, "", v)
          gsub(/"time":[0-9]+/, "", v)
          gsub(/block_number: Some\([0-9]+\)/, "", v)
          gsub(/block_timestamp: Some\([0-9]+\)/, "", v)
          gsub(/drain_duration_ms=[0-9]+/, "", v)
          gsub(/last_processed_block=[0-9]+/, "", v)
          gsub(/subgraph_head=[0-9]+/, "", v)
          gsub(/polls_idle=[0-9]+/, "", v)
          if (v == last[tag]) next
          last[tag] = v
        }
        print "[" c "] " clean; fflush()
      }
    '
    sleep 2
  done
}

# Supervisor: rescan every 10s, attach a tail to each matching container not yet attached. ATTACHED
# only grows -- a recreated container (fresh-deploy) keeps its still-running reattach loop, a newly
# added extra (add-indexers) is picked up next scan. Runs forever as the container's main process.
echo "[dips-logs] starting; auto-discovering DIPs containers (rescan every 10s)"
ATTACHED=" "
while true; do
  for c in $(docker ps --format '{{.Names}}' | grep -E "$MATCH" | sort); do
    case "$ATTACHED" in
      *" $c "*) ;;
      *)
        echo "[dips-logs] attaching: $c"
        tail_one "$c" &
        ATTACHED="$ATTACHED$c "
        ;;
    esac
  done
  sleep 10
done
