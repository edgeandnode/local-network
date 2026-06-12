#!/usr/bin/env bash
# List baked baselines under _snapshots/<recipe>/<fingerprint>/, marking the
# slot that matches each recipe's CURRENT fingerprint (* = a fresh hit today).
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

if ! ls -d _snapshots/*/ >/dev/null 2>&1; then
  echo "no baked baselines (_snapshots/ is empty)"
  exit 0
fi

printf '%-2s %-18s %-14s %-22s %-8s %s\n' "" "RECIPE" "FINGERPRINT" "BAKED_AT" "SIZE" "GIT_SHA"
for manifest in _snapshots/*/*/manifest.json; do
  [ -f "$manifest" ] || continue
  dir=$(dirname "$manifest")
  recipe=$(jq -r '.recipe // "?"' "$manifest")
  fp=$(basename "$dir")
  baked=$(jq -r '.baked_at // "?"' "$manifest")
  sha=$(jq -r '(.git_sha // "?")[0:9]' "$manifest")
  dirty=$(jq -r 'if .git_dirty then "+" else "" end' "$manifest")
  size=$(du -sh "$dir" 2>/dev/null | cut -f1)
  cur=$(./scripts/baseline-fingerprint.sh "$recipe" 2>/dev/null || echo "")
  mark=$([ "$fp" = "$cur" ] && echo "*" || echo " ")
  printf '%-2s %-18s %-14s %-22s %-8s %s%s\n' "$mark" "$recipe" "$fp" "$baked" "$size" "$sha" "$dirty"
done
echo "(* = matches the recipe's current fingerprint — a fresh cache hit)"
