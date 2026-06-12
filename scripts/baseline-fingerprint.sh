#!/usr/bin/env bash
# Compute a content fingerprint for a recipe's baked baseline. Any input that
# affects the baked stack shifts the fingerprint, so a stale cache can never be
# silently reused (the most insidious failure mode for baseline reuse).
#
# Components:
#   - the recipe's fully-resolved env (recipe + fragments + overrides), minus
#     the generated-timestamp comment header — captures CONTRACTS_VERSION,
#     image version pins, REO_MOCK / INDEXING_PAYMENTS_ENABLED / GIP0088_ENABLED,
#     mnemonic, etc.
#   - git tree hash of bake-relevant tracked paths (deploy scripts + compose +
#     the bake/resolve scripts themselves) — config that isn't in env.
#   - hash of uncommitted edits to those paths, so a dirty working tree gets its
#     own cache slot rather than polluting the clean-HEAD one.
#
# Usage: baseline-fingerprint.sh [recipe]   (defaults to the active recipe)
# Prints a 12-hex fingerprint on stdout.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

recipe=$(./scripts/resolve-recipe.sh ${1:+"$1"} --print-recipe)

# Tracked paths whose content affects the baked stack but isn't reflected in
# the resolved env (deploy logic, compose topology, the bake pipeline itself).
PATHS=(containers compose scripts/bake-snapshot.sh scripts/resolve-recipe.sh)

env_hash=$(./scripts/resolve-recipe.sh "$recipe" --print | grep -v '^#' | sha256sum | cut -d' ' -f1)
tree_hash=$(git ls-tree -r HEAD -- "${PATHS[@]}" 2>/dev/null | sha256sum | cut -d' ' -f1)
dirty_hash=$(git diff HEAD -- "${PATHS[@]}" 2>/dev/null | sha256sum | cut -d' ' -f1)

printf '%s|%s|%s' "$env_hash" "$tree_hash" "$dirty_hash" | sha256sum | cut -c1-12
