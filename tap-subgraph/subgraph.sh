#!/bin/sh
set -euf

if [ ! -d "build/semiotic-ai/timeline-aggregation-protocol-subgraph" ]; then
  mkdir -p build/semiotic-ai/timeline-aggregation-protocol-subgraph
  git clone git@github.com:semiotic-ai/timeline-aggregation-protocol-subgraph build/semiotic-ai/timeline-aggregation-protocol-subgraph --branch 'main' --recursive
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

echo "awaiting controller"
until curl -s "http://${CONTROLLER_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done

echo "awaiting IPFS"
until curl -s "http://${IPFS_HOST}:${IPFS_RPC}/api/v0/version" -X POST > /dev/null; do sleep 1; done

echo "awaiting graph-node"
until curl -s "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_STATUS}" >/dev/null; do sleep 1; done

echo "awaiting scalar-tap-contracts"
curl "http://${CONTROLLER_HOST}:${CONTROLLER}/scalar_tap_contracts" >scalar_tap_contracts.json

escrow=$(cat scalar_tap_contracts.json | jq -r '."1337".escrow')
echo "escrow=${escrow}"

cd build/semiotic-ai/timeline-aggregation-protocol-subgraph

response=$(curl -s --max-time 1 "http://${CONTROLLER_HOST}:${CONTROLLER}/escrow_subgraph" || true)
if [ ! -n "$response" ]; then

    # yarn add --dev @graphprotocol/graph-cli
    sed -i "s+http://127.0.0.1:5001+http://${IPFS_HOST}:${IPFS_RPC}+g" package.json
    sed -i "s+http://127.0.0.1:8020+http://${GRAPH_NODE_HOST}:${GRAPH_NODE_ADMIN}+g" package.json
    yq ".dataSources[].source.address=\"${escrow}\"" -i subgraph.yaml
    yq ".dataSources[].network |= \"hardhat\"" -i subgraph.yaml
    yarn codegen
    yarn build
    yarn create-local
    yarn deploy-local --version-label v0.0.1 | tee subgraph-deploy.txt
    subgraph_deployment="$(grep "Build completed: " subgraph-deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"
    echo "subgraph_deployment=${subgraph_deployment}"

    curl "http://${CONTROLLER_HOST}:${CONTROLLER}/escrow_subgraph" -d "${subgraph_deployment}"
else
    echo "already deployed response=${response}"
fi