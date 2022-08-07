#!/bin/sh
. ./prelude.sh

await 'curl -sf localhost:4000'

cd build/edgeandnode/subgraph-studio

export DB_HOST=localhost
export DB_PORT="${POSTGRES_PORT}"
export DB_NAME=local_network_subgraph_studio
export DB_USER="${POSTGRES_USER}"
export DB_PASS="${POSTGRES_PASSWORD}"

yarn db:setup
yarn knex seed:run --specific test-users.ts

psql -w \
  -h localhost \
  -p "${POSTGRES_PORT}" \
  -U "${POSTGRES_USER}" \
  -d local_network_subgraph_studio \
  -c 'update "Users" set "queriesActivated" = true;'
