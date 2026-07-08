#!/bin/bash
# Studio deployment-router env wrapper. Sources local-network .env, exports
# only the values that diverge from studio defaults, then execs the passed
# command. With no args, runs the prod startup (node dist/server.mjs).
set -eu
. /opt/config/.env

# Studio defaults don't match our stack:
export DB_NAME=studio
export DB_USER=postgres
export DB_PASS=postgres
export DATABASE_URL="postgresql://postgres:postgres@postgres:5432/studio"
export REDIS_HOST=studio-redis

# Point at the docker-network address for studio-query-proxy
export QUERY_PROXY_BASE_URL="http://studio-query-proxy:${STUDIO_QUERY_PROXY_PORT:-4002}/query"

# Point subgraph-indexing-request producer to local-network's redpanda:9092
export DEPLOYMENT_ROUTER_SUBGRAPH_INDEXING_REQUESTS_REDPANDA_CONFIG='{"brokers":["redpanda:9092"],"groupId":"studio-indexing-requests","clientId":"studio_deployment_router","topics":["subgraph.indexing.requests"]}'

if [ $# -eq 0 ]; then
  set -- bash -c "cd /app/packages/deployment-router && exec node dist/server.mjs"
fi

exec "$@"
