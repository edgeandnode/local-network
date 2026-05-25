#!/bin/bash

# Seed a fully-verified studio user for an ETH address. Lets the wallet sign in
# via MetaMask and immediately publish a subgraph without email confirmation.
# Wraps subgraph-studio's packages/shared/src/database/seeds/seed-local-user.ts.
#
# Usage: seed-studio-user.sh <eth_address>

set -euo pipefail

ADDRESS="${1:-}"
if [[ -z "$ADDRESS" ]]; then
  echo "Usage: $0 <eth_address>"
  exit 1
fi

# docker compose exec doesn't inherit api.sh's runtime exports — pass the DB
# connection env vars explicitly so the knex CLI hits the right database.
docker compose exec \
  -e ETH_ADDRESS="$ADDRESS" \
  -e DB_NAME=studio \
  -e DB_USER=postgres \
  -e DB_PASS=postgres \
  studio-api bash -c \
    "cd /app/packages/shared && npm run knex -- seed:run --specific seed-local-user.ts"
