#!/bin/sh
. ./prelude.sh

docker_run postgres \
  -p "${POSTGRES_PORT}:5432" \
  --env-file postgres.env \
  -v "$(pwd)/create-tables.sql:/docker-entrypoint-initdb.d/create-tables.sql:ro" \
  postgres:14.5-alpine -cshared_preload_libraries=pg_stat_statements
