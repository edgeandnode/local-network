#!/usr/bin/env bash
# Resolve a recipe to a flat env file (`.env` by default — picked up
# automatically by `docker compose` without needing `--env-file`).
#
# Resolution order (later wins):
#   1. config/<each fragment listed in recipe>
#   2. recipe.env { ... } overrides
#   3. .env.local (gitignored, optional)
#
# Recipe selection (highest precedence first):
#   1. CLI arg: `resolve-recipe.sh <recipe-name>`
#   2. RECIPE env var
#   3. .recipe.local (gitignored, per-checkout override)
#   4. .recipe (optional, committed per-branch default)
#   5. fallback "baseline" (the resolver's hardcoded default)
#
# Output is `KEY="value"` lines suitable for `docker compose` and
# source-able by shell scripts. Shell-style ${VAR} references inside
# fragments are expanded during sourcing, so the resolved output is fully
# materialised (no unresolved references remain).
#
# A `LOCAL_NETWORK_RECIPE=<recipe>` sentinel is always emitted so the
# top-level `${LOCAL_NETWORK_RECIPE:?...}` reference in docker-compose.yaml
# fails fast with a clear error if the user runs `docker compose up`
# before generating .env.

set -euo pipefail

repo_root() {
  local dir
  dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  printf '%s' "$dir"
}
ROOT=$(repo_root)
CONFIG_DIR=$ROOT/config
RECIPES_DIR=$ROOT/recipes

usage() {
  cat <<EOF
usage: $(basename "$0") [recipe-name] [--out PATH] [--print]

Without --out, writes to \$ROOT/.env (picked up automatically by
\`docker compose\`). With --print, writes to stdout.
EOF
}

# --- Parse args ---
recipe_arg=""
out_path="$ROOT/.env"
print_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out) out_path=$2; shift 2 ;;
    --print) print_only=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; usage >&2; exit 2 ;;
    *) recipe_arg=$1; shift ;;
  esac
done

# --- Recipe selection ---
recipe=""
if [ -n "$recipe_arg" ]; then
  recipe=$recipe_arg
elif [ -n "${RECIPE:-}" ]; then
  recipe=$RECIPE
elif [ -f "$ROOT/.recipe.local" ]; then
  recipe=$(head -n 1 "$ROOT/.recipe.local" | tr -d '[:space:]')
elif [ -f "$ROOT/.recipe" ]; then
  recipe=$(head -n 1 "$ROOT/.recipe" | tr -d '[:space:]')
else
  recipe="baseline"
fi

recipe_file="$RECIPES_DIR/${recipe}.json"
if [ ! -f "$recipe_file" ]; then
  echo "recipe '$recipe' not found at $recipe_file" >&2
  echo "available:" >&2
  ls -1 "$RECIPES_DIR"/*.json 2>/dev/null | sed 's,.*/,  ,; s,\.json$,,' >&2
  exit 1
fi

# --- Source fragments + apply overrides via a clean subshell ---
# A subshell with a known starting environment lets us isolate what the
# recipe contributes (vs whatever the parent shell happens to have set).
# The resolved env is the diff between the subshell's `env -0` output
# before and after sourcing.

resolved=$(
  set -a
  # Sentinel: emitted unconditionally so docker-compose.yaml's
  # `${LOCAL_NETWORK_RECIPE:?...}` reference fails fast if .env is missing.
  LOCAL_NETWORK_RECIPE=$recipe
  # Source fragments in declared order.
  for frag in $(jq -r '.fragments[]' "$recipe_file"); do
    frag_path="$CONFIG_DIR/$frag"
    if [ ! -f "$frag_path" ]; then
      echo "fragment '$frag' not found at $frag_path" >&2
      exit 1
    fi
    # shellcheck disable=SC1090
    source "$frag_path"
  done
  # Apply recipe overrides.
  while IFS= read -r kv; do
    eval "$kv"
  done < <(jq -r '.env // {} | to_entries[] | "\(.key)=\(.value | @sh)"' "$recipe_file")
  # Layer .env.local if present.
  if [ -f "$ROOT/.env.local" ]; then
    # shellcheck disable=SC1091
    source "$ROOT/.env.local"
  fi
  set +a
  # Print only the keys that the recipe declares (anything defined by any
  # fragment or override). Keeps unrelated parent-shell vars out of the output.
  declared=$(
    {
      echo LOCAL_NETWORK_RECIPE
      for frag in $(jq -r '.fragments[]' "$recipe_file"); do
        grep -E '^[[:space:]]*[A-Z_][A-Z0-9_]*=' "$CONFIG_DIR/$frag" \
          | sed 's/[[:space:]]*\([A-Z_][A-Z0-9_]*\)=.*/\1/'
      done
      jq -r '.env // {} | keys[]' "$recipe_file"
      [ -f "$ROOT/.env.local" ] && grep -E '^[[:space:]]*[A-Z_][A-Z0-9_]*=' "$ROOT/.env.local" \
        | sed 's/[[:space:]]*\([A-Z_][A-Z0-9_]*\)=.*/\1/' || true
    } | sort -u
  )
  for key in $declared; do
    val=$(printenv "$key" || true)
    # Double-quote, escaping internal \ and " so docker-compose's
    # --env-file parser AND `source` both consume the value identically.
    val=${val//\\/\\\\}
    val=${val//\"/\\\"}
    printf '%s="%s"\n' "$key" "$val"
  done
)

# --- Emit metadata header + resolved env ---
header() {
  cat <<EOF
# ============================================================================
# AUTO-GENERATED — DO NOT EDIT.
# This file is regenerated on every \`just up\` (or any other command that
# resolves the active recipe). Hand edits are lost on the next regeneration.
#
# Source of truth lives in:
#   config/<fragment>.env       — composable env fragments
#   recipes/<recipe-name>.json  — which fragments + per-recipe overrides
#   .env.local                  — your machine-specific overrides (gitignored)
#
# To change which recipe is active:
#   echo <recipe-name> > .recipe.local      (per-checkout default)
#   RECIPE=<recipe-name> just up            (per-invocation)
#   just up <recipe-name>                   (per-invocation, positional)
#
# To re-generate this file: \`just resolve\` or \`just up\`.
# ============================================================================
# Recipe:    $recipe
# Source:    $recipe_file
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

if [ "$print_only" -eq 1 ]; then
  header
  printf '%s\n' "$resolved"
else
  { header; printf '%s\n' "$resolved"; } > "$out_path"
  echo "Resolved recipe '$recipe' → $out_path" >&2
fi
