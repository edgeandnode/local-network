#!/bin/sh
set -euf

if [ ! -d "build/graphprotocol/graph-node" ]; then
  mkdir -p build/graphprotocol/graph-node
  git clone git@github.com:graphprotocol/graph-node build/graphprotocol/graph-node --branch master
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

dynamic_host_setup postgres
dynamic_host_setup controller
dynamic_host_setup ipfs
dynamic_host_setup chain


until curl -s "http://${POSTGRES_HOST}:${POSTGRES}"; [ $? = 52 ]; do sleep 1; done
until curl -s "http://${CONTROLLER_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done
until curl -s "http://${IPFS_HOST}:${IPFS_RPC}/api/v0/version" -X POST > /dev/null; do sleep 1; done

# graph-node has issues if there isn't at least one block on the chain
until curl -s "http://${CHAIN_HOST}:${CHAIN_RPC}" > /dev/null; do sleep 1; done
curl "http://${CHAIN_HOST}:${CHAIN_RPC}" \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"anvil_mine","params":[]}'

export ETHEREUM_RPC="hardhat:http://${CHAIN_HOST}:${CHAIN_RPC}"
export GRAPH_ALLOW_NON_DETERMINISTIC_IPFS=true
export GRAPH_ALLOW_NON_DETERMINISTIC_FULLTEXT_SEARCH=false
export GRAPH_ETH_CALL_FULL_LOG=true
export GRAPH_ETHEREUM_JSON_RPC_TIMEOUT=10
export GRAPH_EXPERIMENTAL_SUBGRAPH_VERSION_SWITCHING_MODE=synced
export GRAPH_IPFS_TIMEOUT=10
export GRAPH_LOG=debug
export GRAPH_LOG_QUERY_TIMING=gql
export GRAPH_NODE_ID=default
export IPFS="http://${IPFS_HOST}:${IPFS_RPC}"
export POSTGRES_URL="postgresql://dev:@${POSTGRES_HOST}:${POSTGRES}/graph_node_1"

cd build/graphprotocol/graph-node
cargo run -p graph-node
