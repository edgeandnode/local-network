#!/bin/sh
. ./prelude.sh

github_clone edgeandnode/subgraph-studio theodus/local-network
cd build/edgeandnode/subgraph-studio

yarn

await "curl -sf localhost:${POSTGRES_PORT}" 52

export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=local_network_subgraph_studio
export DB_USER="${POSTGRES_USER}"
export DB_PASS="${POSTGRES_PASSWORD}"

yarn setup
yarn db:setup
yarn start:api
