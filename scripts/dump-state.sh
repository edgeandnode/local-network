#!/bin/bash
# Capture stack state (compose ps + recent logs) into <outdir> for test-failure
# diagnosis. Echoes the resolved output dir as the last stdout line.
set -u
OUT="${1:-_dumps/dump}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1
mkdir -p "$OUT"
docker compose ps --all >"$OUT/compose-ps.txt" 2>&1 || true
docker compose logs --no-color --tail 500 >"$OUT/compose-logs.txt" 2>&1 || true
echo "$OUT"
