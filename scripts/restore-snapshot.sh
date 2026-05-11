#!/usr/bin/env bash
# Restore a previously-baked snapshot.
#
# Usage:
#   scripts/restore-snapshot.sh [snapshot-dir]    (default: _snapshots/current)
#
# 1. Brings the stack down (preserves volumes by default).
# 2. Wipes + restores each captured volume from the snapshot.
# 3. Restores the recipe selector + .env snapshot from bake time.
# 4. Brings the stack back up via the resolver (idempotent — picks up any
#    drift between bake and now via the existing run.sh skip checks).
#
# Notes:
#   - Restore is destructive on the named volumes. Make sure you don't have
#     live state you want to keep before running.
#   - Anvil's chain time on restore is whatever was on chain at bake time;
#     for tests sensitive to wall-clock alignment, tighten this with
#     `cast rpc evm_setNextBlockTimestamp <now>` post-restore (left as a
#     follow-up — not all stacks need it).

set -euo pipefail

IN=${1:-"_snapshots/current"}
log() { echo "  $*" >&2; }

if [ ! -d "$IN" ]; then
  echo "error: snapshot directory not found: $IN" >&2
  echo "  run 'just bake-snapshot' first to create one." >&2
  exit 1
fi
if [ ! -f "$IN/manifest.json" ]; then
  echo "error: $IN/manifest.json missing — not a valid snapshot" >&2
  exit 1
fi

# Project name: same lookup as bake — read from manifest, fall back to default
project=$(jq -r '.project // "local-network"' "$IN/manifest.json")
recipe=$(jq -r '.recipe // "baseline"' "$IN/manifest.json")
baked_at=$(jq -r '.baked_at // "unknown"' "$IN/manifest.json")
volumes=$(jq -r '.volumes_captured[]' "$IN/manifest.json")

log "restoring snapshot from $IN"
log "  baked_at: $baked_at"
log "  recipe:   $recipe"
log "  project:  $project"
log "  volumes:  $(echo $volumes | tr '\n' ' ')"

# Ensure we have a working .env before invoking compose -----------
if [ -f "$IN/.env" ]; then
  log "restoring .env snapshot from bake time"
  cp "$IN/.env" .env
elif [ ! -f .env ]; then
  log "no .env — running resolver for recipe '$recipe'"
  ./scripts/resolve-recipe.sh "$recipe" >/dev/null
fi

# Bring the stack down so volumes can be replaced safely -------------------
log "bringing stack down (preserves volumes)..."
docker compose --env-file .env down 2>&1 | grep -E "Removed|Error" >&2 || true

# Restore each volume ------------------------------------------------------
for v in $volumes; do
  prefixed="${project}_${v}"
  archive="$IN/volumes/${v}.tar.gz"
  if [ ! -f "$archive" ]; then
    echo "warning: archive missing for $v — skipping" >&2
    continue
  fi
  log "restoring $prefixed ← volumes/${v}.tar.gz"
  # Recreate the volume empty, then untar the snapshot contents into it.
  # gunzip + tar happens inside the alpine container so the host doesn't
  # need any compression tooling.
  docker volume rm "$prefixed" >/dev/null 2>&1 || true
  docker volume create "$prefixed" >/dev/null
  docker run --rm -i -v "$prefixed":/dst alpine:3 \
    sh -c 'cd /dst && tar -xzf -' < "$archive"
done

# Restore recipe selector if captured --------------------------------------
[ -f "$IN/.recipe" ] && cp "$IN/.recipe" .recipe || true
[ -f "$IN/.recipe.local" ] && cp "$IN/.recipe.local" .recipe.local || true

# Bring the stack back up --------------------------------------------------
log "bringing stack up..."
./scripts/resolve-recipe.sh >/dev/null
docker compose --env-file .env up -d 2>&1 | grep -E "Started|Created|Error" >&2 || true

# Advance chain time to host wall clock if behind ---------------------------
# After restore, anvil's last block timestamp is whatever was on chain at bake
# time — possibly hours or days behind real-world time. Off-chain components
# log in real time, so a chain stuck in the past confuses receipts, log
# correlation, period-expiry tests, etc. Push chain time forward to host
# wall clock. Forward-only: evm_setNextBlockTimestamp rejects backward moves,
# so on the rare case where host clock is *behind* chain time (clock skew,
# bake-on-faster-machine), we skip.
log "checking chain time vs host clock..."
# Wait briefly for chain RPC to be responsive.
for _ in 1 2 3 4 5; do
  if docker exec chain cast block-number --rpc-url=http://127.0.0.1:8545 >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
current_chain_ts=$(docker exec chain sh -c "cast block latest --rpc-url=http://127.0.0.1:8545" 2>/dev/null \
  | awk '/^timestamp/ {print $2; exit}')
host_ts=$(date -u +%s)
if [ -z "$current_chain_ts" ] || ! [ "$current_chain_ts" -eq "$current_chain_ts" ] 2>/dev/null; then
  log "couldn't read chain timestamp — skipping time alignment"
elif [ "$host_ts" -gt "$current_chain_ts" ]; then
  delta=$((host_ts - current_chain_ts))
  log "advancing chain time by ${delta}s ($current_chain_ts → $host_ts)"
  docker exec chain sh -c "cast rpc evm_setNextBlockTimestamp $host_ts --rpc-url=http://127.0.0.1:8545" >/dev/null 2>&1
  docker exec chain sh -c "cast rpc anvil_mine 0x1 --rpc-url=http://127.0.0.1:8545" >/dev/null 2>&1
else
  log "chain time already at or ahead of host clock (chain=$current_chain_ts host=$host_ts) — no adjustment"
fi

echo "Restored snapshot from $IN" >&2
echo "  Run 'docker ps' to see service health." >&2
