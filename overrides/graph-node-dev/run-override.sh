#!/bin/bash -l
set -xeu
. /opt/.env


# graph-node has issues if there isn't at least one block on the chain
curl -f "http://chain:${CHAIN_RPC}" \
   -H 'content-type: application/json' \
   -d '{"jsonrpc":"2.0","id":1,"method":"anvil_mine","params":[]}'

export ETHEREUM_RPC="hardhat:http://chain:${CHAIN_RPC}/"
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
    echo "\n"
    echo "Error in process, pausing docker container to allow for inspecting the container state"
    tail -f /dev/null
}

trap handle_error ERR

cargo build --bin graph-node

# Conditionally wrap the binary in gdb if the WAIT_FOR_DEBUG environment variable is set
if [ -n "${WAIT_FOR_DEBUG:-}" ]; then
    echo "\n"
    echo "Waiting for debugger to attach to graph-node..."
    gdbserver :2345 /tmp/graph-node-docker-build/debug/graph-node
else 
    echo "\n"
    echo "Running graph-node without debugger..."
    /tmp/graph-node-docker-build/debug/graph-node
fi

echo "cargo and graph-node exited without error"
