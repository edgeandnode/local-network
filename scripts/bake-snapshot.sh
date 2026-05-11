#!/usr/bin/env bash
# Snapshot the current local-network state into a directory so
# `restore-snapshot.sh` can later bring it back without a cold cold-start.
#
# Usage:
#   scripts/bake-snapshot.sh [output-dir]    (default: _snapshots/current)
#
# Stack must be up + healthy + ready before running. The script briefly
# stops services to capture consistent volume state, then restarts them.
#
# What's captured:
#   - All compose-declared named volumes (chain-data, postgres-data,
#     ipfs-data, config-local, iisa-scores, redpanda-data) as zstd
#     tarballs. Each is copied via a throwaway alpine container to
#     avoid platform-specific local-volume paths.
#   - manifest.json: recipe, timestamp, git SHA + dirty flag, captured
#     volume names, container image digests.
#   - .env: snapshot of the active recipe's materialised env
#     at capture time (so the same recipe restores cleanly).
#
# Future: fingerprinting + multi-snapshot cache. For now, single-slot
# under _snapshots/current/ — re-running bake overwrites.

set -euo pipefail

OUT=${1:-"_snapshots/current"}
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Volumes we know about (compose-declared). Ordered roughly by importance.
VOLUMES=(
  chain-data         # anvil state — contracts, balances, storage
  postgres-data      # graph-node DBs + indexer-agent DB
  ipfs-data          # subgraph artifacts (wasm, schema)
  config-local       # contract address books
  iisa-scores        # IISA scoring persistence (indexing-payments only — empty otherwise)
  redpanda-data      # Kafka topic data
)

# Sanity check: stack should be up + healthy + ready -------------------------
log() { echo "  $*" >&2; }

ready_marker=$(docker ps -a --filter 'name=^ready$' --format '{{.Status}}' 2>/dev/null || true)
case "$ready_marker" in
  Exited*) log "ready container exited cleanly — stack is bakeable" ;;
  Up*) log "ready container still running — start-indexing may not have completed; baking anyway" ;;
  *)
    echo "warning: 'ready' container not found — can't confirm stack is fully bootstrapped." >&2
    echo "  proceed only if you've manually verified all services are healthy." >&2
    ;;
esac

mkdir -p "$OUT"

# Resolve recipe + project --------------------------------------------------
recipe=""
[ -f .recipe.local ] && recipe=$(head -n1 .recipe.local | tr -d '[:space:]')
[ -z "$recipe" ] && [ -f .recipe ] && recipe=$(head -n1 .recipe | tr -d '[:space:]')
[ -z "$recipe" ] && recipe="baseline"

# Project name — compose uses the directory name by default. Capture it
# from a known container's labels rather than guessing.
project=$(docker inspect chain --format '{{ index .Config.Labels "com.docker.compose.project" }}' 2>/dev/null || echo "local-network")

git_sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
git_dirty="false"
git diff-index --quiet HEAD -- 2>/dev/null || git_dirty="true"

log "recipe=$recipe project=$project sha=$git_sha dirty=$git_dirty"

# Stop services for consistent capture --------------------------------------
log "stopping stack for consistent volume capture..."
docker compose --env-file .env stop 2>&1 | grep -E "Stopped|Error" >&2 || true

# Capture each volume -------------------------------------------------------
captured=()
mkdir -p "$OUT/volumes"
for v in "${VOLUMES[@]}"; do
  prefixed="${project}_${v}"
  if ! docker volume inspect "$prefixed" >/dev/null 2>&1; then
    log "skip: volume $prefixed not present"
    continue
  fi
  log "capturing $prefixed → volumes/${v}.tar.gz"
  # Run tar+gzip inside an alpine container so we don't depend on host
  # tooling (zstd in particular isn't always installed). Stream to stdout
  # so we can write atomically via a .tmp suffix on the host.
  docker run --rm \
    -v "$prefixed":/src:ro \
    alpine:3 \
    sh -c 'cd /src && tar -czf - .' \
    > "$OUT/volumes/${v}.tar.gz.tmp"
  mv "$OUT/volumes/${v}.tar.gz.tmp" "$OUT/volumes/${v}.tar.gz"
  captured+=("$v")
done

# Capture image digests so a later restore can detect drift -----------------
log "capturing image digests"
docker compose --env-file .env config --images 2>/dev/null \
  | sort -u > "$OUT/images.txt" || true

# Snapshot the active resolved env ------------------------------------------
cp .env "$OUT/.env" 2>/dev/null || true
[ -f .recipe.local ] && cp .recipe.local "$OUT/.recipe.local"
[ -f .recipe ] && cp .recipe "$OUT/.recipe"

# Write manifest ------------------------------------------------------------
{
  echo "{"
  echo "  \"baked_at\": \"$TS\","
  echo "  \"recipe\": \"$recipe\","
  echo "  \"project\": \"$project\","
  echo "  \"git_sha\": \"$git_sha\","
  echo "  \"git_dirty\": $git_dirty,"
  printf "  \"volumes_captured\": ["
  if [ ${#captured[@]} -gt 0 ]; then
    printf '\n'
    for i in "${!captured[@]}"; do
      printf '    "%s"' "${captured[$i]}"
      [ "$i" -lt $((${#captured[@]}-1)) ] && printf ","
      printf '\n'
    done
    printf "  "
  fi
  echo "],"
  echo "  \"images_file\": \"images.txt\""
  echo "}"
} > "$OUT/manifest.json"

# Resume the stack ----------------------------------------------------------
log "restarting stack..."
docker compose --env-file .env start 2>&1 | grep -E "Started|Error" >&2 || true

size=$(du -sh "$OUT" | cut -f1)
echo "Baked snapshot ($size) → $OUT" >&2
echo "$OUT"
