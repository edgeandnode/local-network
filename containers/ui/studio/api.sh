#!/bin/bash
# Studio API env wrapper. Sources local-network .env, exports only the values
# that diverge from studio's built-in defaults (or that we want explicit for
# clarity), then execs the passed command. With no args, runs the prod startup.
set -eu
. /opt/config/.env

# Studio defaults don't match our stack:
export DB_NAME=studio
export DB_USER=postgres
export DB_PASS=postgres
export DATABASE_URL="postgresql://postgres:postgres@postgres:5432/studio"
export REDIS_HOST=studio-redis
export ALLOWED_IMAGE_HOSTS="http://ipfs:5001"
export INFURA_KEY="unused-local"

# Explicit even though current studio defaults match — pin for clarity:
export REDIS_PORT=6379
export QUERY_NODE_BASE_URL="http://graph-node:8000"
export NETWORK_ID=1337

# Stripe (warning if empty, non-fatal); flow through .env.local overrides
export STRIPE_SECRET_KEY="${STUDIO_STRIPE_SECRET_KEY}"
export STRIPE_PUBLISHABLE_KEY="${STUDIO_STRIPE_PUBLISHABLE_KEY}"

# OrbClient throws on empty — local stubs let the server start
export ORB_API_KEY="${STUDIO_ORB_API_KEY:-local-stub}"
export ORB_GROWTH_PLAN_ID="${STUDIO_ORB_GROWTH_PLAN_ID:-local-stub}"
export ORB_ANALYTICS_PLAN_ID="${STUDIO_ORB_ANALYTICS_PLAN_ID:-local-stub}"

export INDEXING_PAYMENTS_SUBGRAPH_ENABLED=true
# DIPS default chain for subgraphs published to multiple networks. Studio commit
# e454e269 dropped INDEXING_PAYMENTS_SUBGRAPH_URL (per-network URL is now hardcoded
# in the client; local eip155:1337 -> studio-query-proxy:4002). Default already
# matches local; pinned so an upstream default change can't shift local off 1337.
export DIPS_PUBLISHED_DEFAULT_CHAIN_CAIP2ID="eip155:1337"
export GATEWAY_API_KEY="${GATEWAY_API_KEY}"
export LOCAL_GATEWAY_PROXY_URL="http://gateway:7700/api"

if [ $# -eq 0 ]; then
  set -- bash -c "cd /app/packages/shared && bun run db:setup && cd /app/packages/api && exec node ."
fi

exec "$@"
