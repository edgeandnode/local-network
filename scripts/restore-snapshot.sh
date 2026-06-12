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

log() { echo "  $*" >&2; }

# Default input is the fingerprint-resolved slot for the active recipe (FRESH
# if inputs match, else the latest bake with a STALE warning). Pass an explicit
# path to override.
if [ -n "${1:-}" ]; then
  IN=$1
elif ! IN=$(./scripts/baseline-resolve.sh); then
  echo "  bake one first:  just up && just bake-snapshot" >&2
  exit 1
fi

if [ ! -d "$IN" ]; then
  echo "error: snapshot directory not found: $IN" >&2
  echo "  bake one first:  just up && just bake-snapshot" >&2
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

# Align the recipe selector (gitignored .recipe.local) with the restored
# recipe so later bare `just up` / `docker compose` use the matching env.
printf '%s\n' "$recipe" > .recipe.local

# Bring the stack back up using the .env restored above — materialised at
# bake time for THIS recipe. Do NOT re-resolve from the selector here: a
# no-arg `resolve-recipe.sh` regenerates .env from .recipe and can switch
# recipes out from under the restored volumes (the bug that brought a
# restored reo-live snapshot up as indexing-payments — mock REO + dips
# against reo-live state). If the snapshot had no .env, line ~62 already
# resolved it from the manifest recipe.
log "bringing stack up (recipe=$recipe)..."
docker compose --env-file .env up -d 2>&1 | grep -E "Started|Created|Error" >&2 || true

# Realign chain time after restore -----------------------------------------
# The resumed chain restarts near real wall-clock, but the restored contract
# state can hold timestamps far ahead of that: tests advance chain time via
# evm_increaseTime, and that offset doesn't survive the node restart. Left
# alone, stored timestamps (eligibility renewals, thaw deadlines, escrow, …)
# sit "in the future" relative to the block clock — block.timestamp never
# catches up, so period/expiry logic silently misbehaves.
#
# Advance the block clock to max(host wall-clock, baked chain head) + buffer:
# never behind any restored on-chain timestamp, and at least real time so
# off-chain components stay coherent. Forward-only by construction.
log "realigning chain time..."
for _ in 1 2 3 4 5; do
  docker exec chain cast block-number --rpc-url=http://127.0.0.1:8545 >/dev/null 2>&1 && break
  sleep 2
done
current_chain_ts=$(docker exec chain sh -c "cast block latest --rpc-url=http://127.0.0.1:8545" 2>/dev/null \
  | awk '/^timestamp/ {print $2; exit}')
baked_head=$(jq -r '.chain_head_ts // 0' "$IN/manifest.json")
host_ts=$(date -u +%s)
target=$host_ts
[ "$baked_head" -gt "$target" ] 2>/dev/null && target=$baked_head
target=$((target + 10)) # buffer past the last baked block
if [ -z "$current_chain_ts" ] || ! [ "$current_chain_ts" -eq "$current_chain_ts" ] 2>/dev/null; then
  log "couldn't read chain timestamp — skipping time alignment"
elif [ "$target" -gt "$current_chain_ts" ]; then
  log "advancing chain time $current_chain_ts → $target (host=$host_ts baked_head=$baked_head)"
  docker exec chain sh -c "cast rpc evm_setNextBlockTimestamp $target --rpc-url=http://127.0.0.1:8545" >/dev/null 2>&1
  docker exec chain sh -c "cast rpc anvil_mine 0x1 --rpc-url=http://127.0.0.1:8545" >/dev/null 2>&1
else
  log "chain time $current_chain_ts already ≥ target $target — no adjustment"
fi

echo "Restored snapshot from $IN" >&2
echo "  Run 'docker ps' to see service health." >&2
