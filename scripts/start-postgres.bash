#!/usr/bin/env bash
source prelude.bash

docker run --rm \
  -p 5432:5432 \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  -e POSTGRES_USER=postgres \
  -v "$(pwd)/create-tables.sql:/docker-entrypoint-initdb.d/create-tables.sql:ro" \
  timescale/timescaledb:latest-pg12 -cshared_preload_libraries=pg_stat_statements,timescaledb
