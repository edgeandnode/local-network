#!/bin/bash
# shellcheck disable=SC1091
set -eu
. /opt/config/.env
. /opt/shared/lib.sh

graph_epoch_manager=$(contract_addr EpochManager.address horizon)
data_edge=$(contract_addr DataEdge block-oracle)

echo "=== Configuring block-oracle service ==="
mkdir -p /opt/block-oracle && cd /opt/block-oracle
cat >config.toml <<-EOF
blockmeta_auth_token = ""
owner_address = "${DEPLOYER_ADDRESS#0x}"
owner_private_key = "${DEPLOYER_SECRET#0x}"
data_edge_address = "${data_edge#0x}"
epoch_manager_address = "${graph_epoch_manager#0x}"
subgraph_url = "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/block-oracle"
bearer_token = "TODO"
log_level = "trace"
# Default 10 blocks trips under test load: an anvil_mine burst (epoch advance,
# time travel) puts the chain far ahead of the subgraph, spiralling into 2s
# cooldowns. 100 absorbs test bursts while still catching genuine stalls.
freshness_threshold = 100

[protocol_chain]
name = "eip155:1337"
jrpc = "http://chain:8545"
polling_interval_in_seconds = 1

[indexed_chains]
"eip155:1337" = "http://chain:8545"
EOF
echo "generated config.toml"
cat config.toml

echo "=== Starting block-oracle service ==="
sleep 5
exec /usr/local/bin/block-oracle run config.toml
