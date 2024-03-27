#!/bin/sh
set -euf

. ./.env
cd build/graphprotocol/graph-network-subgraph

curl "http://controller:${CONTROLLER}/graph_contracts" >graph_contracts.json

yarn
npx graph create graph-network --node "http://graph-node:${GRAPH_NODE_ADMIN}"

yarn add --dev ts-node
cp ../../../localAddressScript.ts config/
npx ts-node config/localAddressScript.ts
npx mustache ./config/generatedAddresses.json ./config/addresses.template.ts > ./config/addresses.ts

npx mustache ./config/generatedAddresses.json subgraph.template.yaml > subgraph.yaml
npx graph codegen --output-dir src/types/

npx graph deploy graph-network \
  --node "http://graph-node:${GRAPH_NODE_ADMIN}" \
  --ipfs "http://ipfs:${IPFS_RPC}" \
  --version-label 'v0.0.1' | \
  tee deploy.txt

deployment_id="$(grep 'Build completed: ' deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"

curl "http://graph-node:${GRAPH_NODE_ADMIN}" \
  -H 'content-type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"subgraph_reassign\",\"params\":{\"node_id\":\"default\",\"ipfs_hash\":\"${deployment_id}\"}}"

curl "http://controller:${CONTROLLER}/graph_subgraph" -d "${deployment_id}"
