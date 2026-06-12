#!/usr/bin/env bash
# Run a recipe's test set from a clean baked baseline.
#
# 1. Resolve the active recipe (positional arg > RECIPE > .recipe.local >
#    .recipe > baseline) via resolve-recipe.sh --print-recipe.
# 2. Restore _snapshots/<recipe>/ so the run starts from identical clean
#    state — this is the reset hygiene that kills the "shared stack
#    accumulates state across the day" failure mode. Errors with guidance
#    if no baseline is baked for the recipe.
# 3. cargo nextest run --profile <recipe.test_profile>, forwarding extra args.
#
# Usage:
#   just test-set                  # active recipe
#   just test-set reo-live         # explicit recipe
#   just test-set reo-live -E 'test(=eligibility_lifecycle)'
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

# A leading non-flag positional selects the recipe; everything else passes
# through to nextest.
recipe_arg=""
case "${1:-}" in
  "" | -*) ;;
  *) recipe_arg=$1; shift ;;
esac

recipe=$(./scripts/resolve-recipe.sh ${recipe_arg:+"$recipe_arg"} --print-recipe)
recipe_file="recipes/${recipe}.json"
profile=$(jq -r '.test_profile // "default"' "$recipe_file")

# Resolve the baked baseline by fingerprint (FRESH if inputs unchanged, else
# the latest bake with a STALE warning). baseline-resolve prints the slot dir.
if ! snap=$(./scripts/baseline-resolve.sh "$recipe"); then
  echo "  bring the stack up on this recipe and bake one first:" >&2
  echo "    just up $recipe && just bake-snapshot" >&2
  exit 1
fi

echo "==> test-set: recipe=$recipe  profile=$profile  baseline=$snap" >&2
echo "==> restoring clean baseline (destructive on named volumes)…" >&2
./scripts/restore-snapshot.sh "$snap"

# Wait for the stack to finish bootstrapping. The one-shot `ready` container
# exits 0 once start-indexing completes; restore re-runs it against the
# restored volumes. Don't race nextest against a half-booted stack.
echo "==> waiting for stack readiness (ready container)…" >&2
deadline=$(( $(date +%s) + 300 ))
while :; do
  status=$(docker inspect ready --format '{{.State.Status}}:{{.State.ExitCode}}' 2>/dev/null || echo missing)
  case "$status" in
    exited:0) echo "  ready ✓" >&2; break ;;
    exited:*) echo "  warning: ready exited non-zero ($status) — running anyway" >&2; break ;;
  esac
  if [ "$(date +%s)" -gt "$deadline" ]; then
    echo "  warning: stack not ready after 300s ($status) — running anyway" >&2; break
  fi
  sleep 3
done

echo "==> running profile '$profile'…" >&2
cd tests
exec cargo nextest run --no-capture --no-fail-fast --profile "$profile" "$@"
