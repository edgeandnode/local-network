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

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --force/--rebake bakes even on a cache hit; a positional arg is an explicit
# output dir (bypasses fingerprint keying entirely).
force=0
out_arg=""
for a in "$@"; do
  case "$a" in
    --force | --rebake) force=1 ;;
    *) out_arg=$a ;;
  esac
done

# Recipe the running stack was brought up with — read from the materialised
# .env (its LOCAL_NETWORK_RECIPE sentinel) so the snapshot is keyed to what's
# actually running. Falls back to the recipe selector, then "baseline".
recipe=$(grep -E '^LOCAL_NETWORK_RECIPE=' .env 2>/dev/null | head -1 | cut -d'"' -f2)
[ -z "$recipe" ] && recipe=$(./scripts/resolve-recipe.sh --print-recipe 2>/dev/null || echo baseline)

# Fingerprint the inputs that produced this stack, and slot the snapshot under
# _snapshots/<recipe>/<fingerprint>/ so distinct states (branches, contract
# bumps, mode toggles) coexist and a stale cache can't be silently reused. An
# explicit positional path overrides the keyed slot.
fp=$(./scripts/baseline-fingerprint.sh "$recipe")
OUT=${out_arg:-"_snapshots/$recipe/$fp"}

# Cache hit: this exact fingerprint is already baked — skip unless --force.
if [ -z "$out_arg" ] && [ "$force" -eq 0 ] && [ -f "$OUT/manifest.json" ]; then
  echo "cache hit: recipe '$recipe' fingerprint '$fp' already baked at $OUT" >&2
  echo "  (nothing changed since the last bake; use --force to rebake)" >&2
  echo "$OUT"
  exit 0
fi

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

# Project name — compose uses the directory name by default. Capture it
# from a known container's labels rather than guessing.
project=$(docker inspect chain --format '{{ index .Config.Labels "com.docker.compose.project" }}' 2>/dev/null || echo "local-network")

git_sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
git_dirty="false"
git diff-index --quiet HEAD -- 2>/dev/null || git_dirty="true"

log "recipe=$recipe project=$project sha=$git_sha dirty=$git_dirty"

# Chain head timestamp at bake time (while the chain is still up). Tests can
# advance chain time far past real time via evm_increaseTime, so contract
# storage may hold timestamps well ahead of wall-clock. Restore uses this to
# advance the resumed chain past them, so no on-chain timestamp ends up "in
# the future" relative to the block clock after restart.
chain_head_ts=$(docker exec chain cast block latest --field timestamp \
  --rpc-url=http://127.0.0.1:8545 2>/dev/null | tr -dc '0-9' || true)
[ -z "$chain_head_ts" ] && chain_head_ts=0
log "chain_head_ts=$chain_head_ts"

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
  echo "  \"fingerprint\": \"$fp\","
  echo "  \"chain_head_ts\": $chain_head_ts,"
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

# Record this fingerprint as the recipe's latest bake (used as the STALE
# fallback by baseline-resolve.sh). Only for fingerprint-keyed slots.
if [ -z "$out_arg" ]; then
  printf '%s\n' "$fp" > "_snapshots/$recipe/latest"
fi

# Resume the stack ----------------------------------------------------------
log "restarting stack..."
docker compose --env-file .env start 2>&1 | grep -E "Started|Error" >&2 || true

size=$(du -sh "$OUT" | cut -f1)
echo "Baked snapshot ($size) → $OUT" >&2
echo "$OUT"
