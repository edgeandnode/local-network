#!/bin/bash
# Studio query-proxy env wrapper. Sources local-network .env, exports only the
# values that diverge from studio defaults, then execs the passed command.
# With no args, runs the prod startup (node dist/server.mjs).
set -eu
. /opt/config/.env

# Studio defaults don't match our stack:
export DB_NAME=studio
export DB_USER=postgres
export DB_PASS=postgres
export DATABASE_URL="postgresql://postgres:postgres@postgres:5432/studio"
export REDIS_URL="redis://studio-redis:6379"

if [ $# -eq 0 ]; then
  set -- bash -c "cd /app/packages/query-proxy && exec node dist/server.mjs"
fi

exec "$@"
