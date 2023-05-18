#!/bin/sh
set -euf

if [ ! -d "build/edgeandnode/subgraph-studio" ]; then
    mkdir -p build/edgeandnode/subgraph-studio
    git clone git@github.com:edgeandnode/subgraph-studio build/edgeandnode/subgraph-studio --branch 'v0.16.13'
fi

. ./.env

cd build/edgeandnode/subgraph-studio
cp ../../../studio/create-users.ts packages/shared/src/database/seeds/test-users.ts

export DB_HOST="${DOCKER_GATEWAY_HOST:-host.docker.internal}"
export DB_NAME=subgraph_studio
export DB_PASS=
export DB_PORT="${POSTGRES}"
export DB_USER=dev

yarn setup
yarn db:setup
yarn start:api
