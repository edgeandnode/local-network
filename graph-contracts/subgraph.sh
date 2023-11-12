#!/bin/sh
set -euf

if [ ! -d "build/graphprotocol/graph-network-subgraph" ]; then
  mkdir -p build/graphprotocol/graph-network-subgraph
  git clone git@github.com:graphprotocol/graph-network-subgraph build/graphprotocol/graph-network-subgraph --branch 'master'
fi

. ./.env

echo "awaiting graph-node"
until curl -s "http://${DOCKER_GATEWAY_HOST}:${GRAPH_NODE_STATUS}" >/dev/null; do sleep 1; done

cd build/graphprotocol/graph-network-subgraph

echo "awaiting contracts"
curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/graph_contracts" >graph_contracts.json

yarn
npx graph create graph-network --node "http://${DOCKER_GATEWAY_HOST}:${GRAPH_NODE_ADMIN}"
yarn prep:no-ipfs

yarn add --dev ts-node
cp ../../../graph-contracts/localAddressScript.ts config/
npx ts-node config/localAddressScript.ts
npx mustache ./config/generatedAddresses.json ./config/addresses.template.ts > ./config/addresses.ts

npx mustache ./config/generatedAddresses.json subgraph.template.yaml > subgraph.yaml
npx graph codegen --output-dir src/types/

npx graph deploy graph-network \
  --node "http://${DOCKER_GATEWAY_HOST}:${GRAPH_NODE_ADMIN}" \
  --ipfs "http://${DOCKER_GATEWAY_HOST}:${IPFS_RPC}" \
  --version-label 'v0.0.1' | \
  tee deploy.txt

deployment_id="$(grep 'Build completed: ' deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"

curl "http://${DOCKER_GATEWAY_HOST}:${GRAPH_NODE_ADMIN}" \
  -H 'content-type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"subgraph_reassign\",\"params\":{\"node_id\":\"default\",\"ipfs_hash\":\"${deployment_id}\"}}"

curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/graph_subgraph" -d "${deployment_id}"
