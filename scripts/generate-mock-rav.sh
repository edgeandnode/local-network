#!/usr/bin/env bash
#
# Generate a mock signed RAV and insert it into the database.
#
# Usage: ./generate-mock-rav.sh <allocation-id> [--value 0.1] [--db postgres://...]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../.env
. "$REPO_ROOT/.env"
[ -f "$REPO_ROOT/.env.local" ] && . "$REPO_ROOT/.env.local"

# shellcheck source=../shared/lib.sh
. "$REPO_ROOT/shared/lib.sh"

ALLOC_ID="${1:-}"
if [ -z "$ALLOC_ID" ]; then
  echo "Usage: $0 <allocation-id> [--value 0.1] [--db postgres://...]"
  exit 1
fi
shift

CHAIN_HOST="${CHAIN_HOST:-localhost}"
RPC_URL="http://${CHAIN_HOST}:${CHAIN_RPC_PORT}"

echo "Fetching contract addresses..."
COLLECTOR=$(contract_addr GraphTallyCollector.address horizon)
echo "  GraphTallyCollector: $COLLECTOR"

DATA_SERVICE=$(contract_addr SubgraphService.address subgraph-service)
echo "  SubgraphService: $DATA_SERVICE"

echo "  Allocation ID: $ALLOC_ID"

echo "Fetching current block timestamp..."
BLOCK_TIMESTAMP=$(cast block latest --field timestamp --rpc-url="$RPC_URL")
# Convert to nanoseconds and subtract 10 seconds to be behind chainhead
TIMESTAMP_NS=$(( (BLOCK_TIMESTAMP - 10) * 1000000000 ))
echo "  Timestamp (ns): $TIMESTAMP_NS"

echo ""
echo "Generating mock RAV..."
node "$SCRIPT_DIR/js/generate-mock-rav.mjs" \
  --allocation-id "$ALLOC_ID" \
  --data-service "$DATA_SERVICE" \
  --collector "$COLLECTOR" \
  --timestamp-ns "$TIMESTAMP_NS" \
  "$@"
