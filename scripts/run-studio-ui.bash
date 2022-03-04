#!/usr/bin/env bash
source prelude.bash

cd projects/edgeandnode/subgraph-studio

export NODE_ENV=development

export STUDIO_GRAPHQL_HTTP_URI=http://localhost:4000/graphql
export STUDIO_GRAPHQL_WS_URI=ws://localhost:4000/graphql
export IPFS_URI="${IPFS}"
export NETWORK_ID="${ETHEREUM_NETWORK_ID}"
export PUBLIC_URL=''

yarn dev:ui
