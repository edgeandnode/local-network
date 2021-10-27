#!/usr/bin/env bash
source prelude.bash

cd projects/edgeandnode/subgraph-studio

POSTGRES_USERNAME=postgres

export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=local_network_subgraph_studio
export DB_USER="${POSTGRES_USERNAME}"
# export DB_PASS="${POSTGRES_PASSWORD}"

yarn knex seed:run --specific test-users.ts

psql \
  -h localhost \
  -U "${POSTGRES_USERNAME}" \
  -d local_network_subgraph_studio \
  -c 'update "Users" set "queriesActivated" = true;'
