#!/bin/sh
set -eu
. /opt/config/.env

# Allow env var overrides for multi-indexer support
POSTGRES_HOST="${POSTGRES_HOST:-postgres}"

# graph-node has issues if there isn't at least one block on the chain
curl -sf "http://chain:${CHAIN_RPC_PORT}" \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"anvil_mine","params":[]}'

export GRAPH_ALLOW_NON_DETERMINISTIC_FULLTEXT_SEARCH="true"
export IPFS="http://ipfs:${IPFS_RPC_PORT}"

# Use a TOML config (not env-var flags) because the [log_store] section that
# enables file-based subgraph log storage (queryable via the _logs GraphQL
# field) is only wired through GRAPH_NODE_CONFIG. The env-var path hardcodes
# log_store=None. Values below mirror the previous env-var config exactly
# (default node id, hardhat network, traces+archive features, pool size 10).
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
graph-node
