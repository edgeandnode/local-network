#!/bin/bash -l
set -xeu
. /opt/.env


# graph-node has issues if there isn't at least one block on the chain
curl -f "http://chain:${CHAIN_RPC}" \
   -H 'content-type: application/json' \
   -d '{"jsonrpc":"2.0","id":1,"method":"anvil_mine","params":[]}'

export ETHEREUM_RPC="local:http://chain:${CHAIN_RPC}/"
export GRAPH_ALLOW_NON_DETERMINISTIC_FULLTEXT_SEARCH="true"
unset GRAPH_NODE_CONFIG
export IPFS="http://ipfs:${IPFS_RPC}"
export POSTGRES_URL="postgresql://postgres:@postgres:${POSTGRES}/graph_node_1"

export RUSTUP_HOME=/usr/local/rustup
export CARGO_HOME=/usr/local/cargo
export PATH=/usr/local/cargo/bin:$PATH

cd /opt/graph-node-source-root

# These are volumes mounted at this same location on the host.
export CARGO_TARGET_DIR=/tmp/graph-node-docker-build
export CARGO_HOME=/tmp/graph-node-cargo-home

handle_error() {
    echo "Error in process, pausing docker container to allow for inspecting the container state"
    tail -f /dev/null
}

trap handle_error ERR

cargo run --bin graph-node

echo "cargo and graph-node exited without error"
