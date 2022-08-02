#!/bin/sh
. ./prelude.sh

export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=local_network_subgraph_studio
export DB_USER="${POSTGRES_USER}"
export DB_PASS="${POSTGRES_PASSWORD}"

export JWT_SIGNING_SECRET="supersecret"

auth_file="${PWD}/build/studio-admin-auth.txt"
cd build/edgeandnode/subgraph-studio/packages/admin-api
yarn issue-auth-token | grep Bearer | awk '{print $2}' > "${auth_file}"

trap "rm -f ${auth_file}" INT

cd ../..
yarn dev:admin-api
