#!/usr/bin/env bash
source prelude.bash

cd projects/edgeandnode/subgraph-studio

export NODE_ENV=development

export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=local_network_subgraph_studio
export DB_USER="${POSTGRES_USERNAME}"
export DB_PASS="${POSTGRES_PASSWORD}"

yarn setup
cd packages/api
yarn start |& tee /tmp/studio-api.log
