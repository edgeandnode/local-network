#!/bin/sh
. ./prelude.sh

github_clone graphprotocol/graph-network-subgraph theodus/local-network

await "curl -sf localhost:${IPFS_PORT}" 22
await "curl -sf localhost:${GRAPH_NODE_STATUS_PORT}" 22
await_ready common-ts

cd build/graphprotocol/graph-network-subgraph

yalc link @graphprotocol/contracts
yalc link @graphprotocol/common-ts
yalc update
yarn --non-interactive

npx graph create \
    --node "http://127.0.0.1:${GRAPH_NODE_STATUS_PORT}" \
    graphprotocol/graph-network

yarn prep:no-ipfs

ts-node config/hardhatAddressScript.ts
npx mustache ./config/generatedAddresses.json ./config/addresses.template.ts > ./config/addresses.ts

npx mustache ./config/generatedAddresses.json subgraph.template.yaml > subgraph.yaml
npx graph codegen --output-dir src/types/

npx graph deploy graphprotocol/graph-network \
    --ipfs "http://127.0.0.1:${IPFS_PORT}" \
    --node "http://127.0.0.1:${GRAPH_NODE_STATUS_PORT}" \
    --version-label $(jq .label ../../../versionMetadata.json)

cd -

signal_ready graph-subgraph
