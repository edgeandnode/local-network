#!/bin/sh
# Merge + ANSI-strip + pre-filter the five DIPs containers into ONE plain-text stream so Dozzle
# (whose search is per-container and breaks on color codes) shows and filters them reliably as a
# single container. Runs standalone so it survives /fresh-deploy; the reattach loop recovers on recreate.

CONTAINERS="dipper indexer-agent indexer-service iisa graph-node"
ESC=$(printf '\033')

# Idle-noise + non-DIPs chatter, matched after ANSI strip. Goal: idle near-silent, lights up on real DIPs
# events. Drops graph-node empty/epoch-decode/pruning, service spans+query-fee, dipper heartbeats, health-
# checks, agent trace + POI-loop + reconciliation plumbing. Keeps syncing, escrow/topology, accepts, rules.
NOISE='triggers: 0,|entities: 0,|Syncing [0-9]+ blocks from Ethereum|data_source: DataEdge|Start pruning|Finished pruning|Found [0-9]+ triggers|Applying [0-9]+ entity'
NOISE="$NOISE|uri: /status|router::http_request|routes::status|at crates/|tap_receipt|auth::tap|value_check|request_handler|pagination complete"
NOISE="$NOISE|Accepting new connection|starting new connection|starting expiration scan|no expired agreements|paginated_client"
NOISE="$NOISE|GET /health|\"msg\":\"GET / 200|\"level\":10,|No pending RAVs"
NOISE="$NOISE|presentPOI|Identify expiring allocations|Expired allocations found"
NOISE="$NOISE|0 pending, 0 active accepted|No collectable agreements found|No recently closed allocations|No deployment changes are necessary"
NOISE="$NOISE|[Rr]econcil|Fetch subgraph deployment assignments|Fetching mapped subgraph deployment|Fetching active deployments|Refresh eligible allocations|Fetch recently closed allocations|isPaused|Execute 'actions' query|Ensuring indexing rules for DIPs|Fetching indexing rules|Fetch Active allocations|Query subgraph deployments|Finished fetching "

# Dedupe-on-change for unchanging state heartbeats (escrow / allocations / ETH balance / chain-listener):
# strip the volatile parts (timestamps, block numbers, poll counters) to a value key, then suppress a line
# only when that value matches the last one printed. First sighting prints; changes reprint; errors pass.
tail_one() {
  c="$1"
  while true; do
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
    echo "[dips-logs] $c stream ended; reattaching in 2s"
    sleep 2
  done
}

echo "[dips-logs] starting; merging: $CONTAINERS"
for c in $CONTAINERS; do
  tail_one "$c" &
done
wait
