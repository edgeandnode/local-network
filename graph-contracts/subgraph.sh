#!/bin/sh
set -euf

if [ ! -d "build/graphprotocol/graph-network-subgraph" ]; then
  mkdir -p build/graphprotocol/graph-network-subgraph
  git clone git@github.com:graphprotocol/graph-network-subgraph build/graphprotocol/graph-network-subgraph --branch 'master'
fi

. ./.env


dynamic_host_setup() {
    if [ $# -eq 0 ]; then
        echo "No name provided."
        return 1
    fi

    # Convert the name to uppercase for the variable name
    local name_upper=$(echo $1 | tr '-' '_' | tr '[:lower:]' '[:upper:]')
    local export_name="${name_upper}_HOST"
    local host_name="$1"

    # Directly use 'eval' for dynamic variable assignment to avoid bad substitution
    eval export ${export_name}="${host_name}"
    if ! getent hosts "${host_name}" >/dev/null; then
        eval export ${export_name}="\$DOCKER_GATEWAY_HOST"
    fi

    # Use 'eval' for echoing dynamic variable value
    eval echo "${export_name} is set to \$${export_name}"
}

dynamic_host_setup graph-node
dynamic_host_setup chain
dynamic_host_setup controller
dynamic_host_setup ipfs


echo "awaiting graph-node"
until curl -s "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_STATUS}" >/dev/null; do sleep 1; done

cd build/graphprotocol/graph-network-subgraph

echo "awaiting contracts"
curl "http://${CONTROLLER_HOST}:${CONTROLLER}/graph_contracts" >graph_contracts.json

yarn
npx graph create graph-network --node "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_ADMIN}"
# yarn prep:no-ipfs

# yarn add --dev ts-node
cp ../../../graph-contracts/localAddressScript.ts config/
npx ts-node config/localAddressScript.ts
npx mustache ./config/generatedAddresses.json ./config/addresses.template.ts > ./config/addresses.ts

npx mustache ./config/generatedAddresses.json subgraph.template.yaml > subgraph.yaml
npx graph codegen --output-dir src/types/

npx graph deploy graph-network \
  --node "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_ADMIN}" \
  --ipfs "http://${IPFS_HOST}:${IPFS_RPC}" \
  --version-label 'v0.0.1' | \
  tee deploy.txt

deployment_id="$(grep 'Build completed: ' deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"

curl "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_ADMIN}" \
  -H 'content-type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"subgraph_reassign\",\"params\":{\"node_id\":\"default\",\"ipfs_hash\":\"${deployment_id}\"}}"

curl "http://${CONTROLLER_HOST}:${CONTROLLER}/graph_subgraph" -d "${deployment_id}"
