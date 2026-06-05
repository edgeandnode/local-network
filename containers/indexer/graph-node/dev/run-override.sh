#!/bin/bash -l
set -xeu
. /opt/config/.env

# graph-node has issues if there isn't at least one block on the chain
curl -sf "http://chain:${CHAIN_RPC_PORT}" \
   -H 'content-type: application/json' \
   -d '{"jsonrpc":"2.0","id":1,"method":"anvil_mine","params":[]}'

export GRAPH_ALLOW_NON_DETERMINISTIC_FULLTEXT_SEARCH="true"
export IPFS="http://ipfs:${IPFS_RPC_PORT}"

# Use a TOML config (not env-var flags) because the [log_store] section that
# enables file-based subgraph log storage (queryable via the _logs GraphQL
# field) is only wired through GRAPH_NODE_CONFIG. The env-var path hardcodes
# log_store=None. Values below mirror the previous env-var config exactly.
POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
LOG_DIR="/var/log/graph-node/subgraph-logs"
mkdir -p "$LOG_DIR"

cat > /opt/graph-node-config.toml <<EOF
[store]
[store.primary]
connection = "postgresql://postgres:postgres@${POSTGRES_HOST}:${POSTGRES_PORT}/graph_node_1"
pool_size = 10

[deployment]
[[deployment.rule]]
store = "primary"
indexers = ["default"]

[chains]
ingestor = "default"

[chains.hardhat]
shard = "primary"
provider = [
  { label = "hardhat", url = "http://chain:${CHAIN_RPC_PORT}/", features = ["traces", "archive"] }
]

[log_store]
backend = "file"
directory = "$LOG_DIR"
retention_hours = 0
EOF

export GRAPH_NODE_CONFIG=/opt/graph-node-config.toml

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
