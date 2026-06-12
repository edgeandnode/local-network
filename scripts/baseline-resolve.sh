#!/usr/bin/env bash
# Resolve which baked baseline to use for a recipe, keyed by fingerprint.
# Prints the snapshot directory on stdout. Signals freshness on stderr + exit:
#   exit 0 + "FRESH"  : exact fingerprint match (inputs unchanged since bake)
#   exit 0 + "STALE"  : no exact match; fell back to the recipe's latest bake
#                       (inputs drifted — reconcile-on-up runs, or rebake)
#   exit 3 + "MISSING": nothing baked for this recipe
#
# Usage: baseline-resolve.sh [recipe]   (defaults to the active recipe)
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

recipe=$(./scripts/resolve-recipe.sh ${1:+"$1"} --print-recipe)
fp=$(./scripts/baseline-fingerprint.sh "$recipe")
base="_snapshots/$recipe"

if [ -f "$base/$fp/manifest.json" ]; then
  echo "baseline FRESH: recipe=$recipe fingerprint=$fp" >&2
  printf '%s\n' "$base/$fp"
  exit 0
fi

if [ -f "$base/latest" ]; then
  latest=$(cat "$base/latest")
  if [ -n "$latest" ] && [ -f "$base/$latest/manifest.json" ]; then
    echo "baseline STALE: recipe=$recipe wanted fingerprint=$fp, using latest bake=$latest" >&2
    echo "  inputs drifted since bake — bringup reconciles idempotently, or rebake: just bake-snapshot --force" >&2
    printf '%s\n' "$base/$latest"
    exit 0
  fi
fi

echo "baseline MISSING: nothing baked for recipe '$recipe' under $base/" >&2
exit 3
