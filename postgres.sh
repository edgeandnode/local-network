#!/bin/sh
. ./prelude.sh

docker_run postgres \
  -p "${POSTGRES_PORT}:5432" \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  -e "POSTGRES_USER=${POSTGRES_USER}" \
  -e "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" \
  -v "$(pwd)/create-tables.sql:/docker-entrypoint-initdb.d/create-tables.sql:ro" \
  timescale/timescaledb:latest-pg14 -cshared_preload_libraries=pg_stat_statements,timescaledb
