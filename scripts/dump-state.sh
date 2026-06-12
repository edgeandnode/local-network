#!/usr/bin/env bash
# Capture local-network state to a directory for offline debugging.
#
# Usage:
#   scripts/dump-state.sh [output-dir]
#
# Default output: _dumps/<UTC-timestamp>[-<label>]
#
# Captures (best-effort — missing pieces don't fail the dump):
#   - Active recipe + resolved env
#   - All container statuses, health, last-N logs
#   - Anvil chain state dump + chain head
#   - Indexer-agent management API state (registration, allocations, rules)
#   - Per-test indexer compose projects (if any IndexerHandle tests are mid-run)
#   - SUMMARY.md describing what's there

set -uo pipefail

LOG_TAIL_LINES=${DUMP_LOG_TAIL_LINES:-500}
TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT=${1:-"_dumps/${TS}"}
mkdir -p "$OUT"

echo "Dumping state → $OUT" >&2

# Helpers --------------------------------------------------------------------
log()   { echo "  $*" >&2; }
maybe() { "$@" 2>/dev/null || true; }

# Resolve recipe + env -------------------------------------------------------
log "recipe / env"
[ -f .recipe.local ]  && cp .recipe.local  "$OUT/.recipe.local"
[ -f .recipe ]        && cp .recipe        "$OUT/.recipe"
[ -f .env ]  && cp .env  "$OUT/.env"
[ -f .env.local ]     && cp .env.local     "$OUT/.env.local"

# Recipe selection (mirrors resolver fallback logic)
recipe=""
[ -f .recipe.local ] && recipe=$(head -n1 .recipe.local | tr -d '[:space:]')
[ -z "$recipe" ] && [ -f .recipe ] && recipe=$(head -n1 .recipe | tr -d '[:space:]')
[ -z "$recipe" ] && recipe="baseline"

# Container surface ----------------------------------------------------------
log "containers"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}\t{{.Image}}" \
  > "$OUT/containers.txt" 2>&1 || true

# Per-container logs + state -------------------------------------------------
mkdir -p "$OUT/logs" "$OUT/inspect"
for c in $(docker ps -a --format '{{.Names}}'); do
  docker logs --tail "$LOG_TAIL_LINES" "$c" > "$OUT/logs/$c.log" 2>&1 || true
  docker inspect "$c" --format '{{json .State}}' \
    | maybe jq '.' > "$OUT/inspect/$c-state.json"
done

# Anvil chain state ----------------------------------------------------------
log "chain"
mkdir -p "$OUT/chain"
# anvil_dumpState — full chain state (verbose, can be large)
docker exec chain cast rpc anvil_dumpState --rpc-url=http://127.0.0.1:8545 \
  > "$OUT/chain/anvil-state.json" 2>"$OUT/chain/anvil-state.err" || true
# Latest block + chain id (small, always useful)
docker exec chain cast block latest --rpc-url=http://127.0.0.1:8545 \
  > "$OUT/chain/latest-block.txt" 2>&1 || true
docker exec chain cast chain-id --rpc-url=http://127.0.0.1:8545 \
  > "$OUT/chain/chain-id.txt" 2>&1 || true

# Indexer-agent management API ----------------------------------------------
log "indexer-agent"
mkdir -p "$OUT/agent"
agent_query() {
  local name=$1; shift
  local query=$*
  # Build the JSON body with jq to avoid shell-quoting hell — GraphQL queries
  # contain `"` for string literals which collide with sh -c's outer quotes.
  local body
  body=$(jq -nc --arg q "$query" '{query:$q}')
  docker exec -i indexer-agent curl -s -X POST \
    -H 'content-type: application/json' \
    --data-binary @- \
    http://127.0.0.1:7600/ <<< "$body" \
    | maybe jq '.' > "$OUT/agent/$name.json"
}
agent_query registration  '{ indexerRegistration(protocolNetwork: "eip155:1337") { address registered url } }'
agent_query allocations   '{ indexerAllocations(protocolNetwork: "eip155:1337") { id subgraphDeployment allocatedTokens createdAtEpoch closedAtEpoch status } }'
agent_query indexingRules '{ indexingRules(protocolNetwork: "eip155:1337", merged: true) { identifier identifierType decisionBasis allocationAmount } }'

# Per-test indexer compose projects -----------------------------------------
test_projects=$(docker ps -a --format '{{.Names}}' \
  | grep -oE 'local-network-test-[a-z0-9-]+' \
  | grep -oE 'local-network-test-[a-z0-9]+(-[a-z0-9]+)*?(?=-(postgres|graph-node|subgraph-deploy|indexer-agent)-1$)' 2>/dev/null \
  | sort -u || true)
# Fallback if grep -P unavailable: derive project names by stripping known service suffixes
if [ -z "${test_projects:-}" ]; then
  test_projects=$(docker ps -a --format '{{.Names}}' \
    | grep '^local-network-test-' \
    | sed -E 's/-(postgres|graph-node|subgraph-deploy|indexer-agent)-1$//' \
    | sort -u || true)
fi
if [ -n "${test_projects:-}" ]; then
  log "per-test indexer projects: $(echo $test_projects | tr ' ' ',')"
  mkdir -p "$OUT/per-test-indexers"
  for proj in $test_projects; do
    mkdir -p "$OUT/per-test-indexers/$proj"
    for c in $(docker ps -a --format '{{.Names}}' | grep "^$proj-"); do
      docker logs --tail "$LOG_TAIL_LINES" "$c" \
        > "$OUT/per-test-indexers/$proj/$c.log" 2>&1 || true
      docker inspect "$c" --format '{{json .State}}' \
        | maybe jq '.' > "$OUT/per-test-indexers/$proj/$c-state.json"
    done
  done
fi

# Compose config (for reference) --------------------------------------------
log "compose config"
docker compose --env-file .env config 2>/dev/null \
  > "$OUT/compose-config.yaml" || true

# Summary -------------------------------------------------------------------
container_count=$(docker ps -q | wc -l | tr -d ' ')
container_total=$(docker ps -aq | wc -l | tr -d ' ')
test_count=$(echo "${test_projects:-}" | wc -w | tr -d ' ')
size=$(du -sh "$OUT" | cut -f1)

cat > "$OUT/SUMMARY.md" <<EOF
# Local-network state dump

- **Captured**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- **Recipe**: $recipe
- **Containers**: $container_count running ($container_total total)
- **Per-test indexer projects**: $test_count
- **Dump size**: $size

## Layout

| Path | Contents |
|---|---|
| \`.recipe\` / \`.recipe.local\` / \`.env\` / \`.env.local\` | Recipe selection + materialised env at capture time |
| \`containers.txt\` | \`docker ps -a\` table |
| \`logs/<name>.log\` | Last $LOG_TAIL_LINES log lines per container |
| \`inspect/<name>-state.json\` | Container state (incl. exit code, OOM flag, healthcheck history) |
| \`chain/anvil-state.json\` | Full anvil chain state dump (loadable via \`anvil_loadState\`) |
| \`chain/latest-block.txt\` / \`chain-id.txt\` | Quick chain head info |
| \`agent/<query>.json\` | Indexer-agent management-API responses (registration, allocations, indexing rules) |
| \`per-test-indexers/<project>/\` | Any active IndexerHandle compose projects (logs + state per service) |
| \`compose-config.yaml\` | Resolved compose config (for cross-referencing service definitions vs runtime state) |
EOF

echo "Done. $size in $OUT" >&2
echo "$OUT"
