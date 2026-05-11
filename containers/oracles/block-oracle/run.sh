#!/bin/bash
set -eu
. /opt/config/.env
. /opt/shared/lib.sh

graph_epoch_manager=$(contract_addr EpochManager.address horizon)
data_edge=$(contract_addr DataEdge block-oracle)

echo "=== Configuring block-oracle service ==="
cd /opt/block-oracle
cat >config.toml <<-EOF
blockmeta_auth_token = ""
owner_address = "${DEPLOYER_ADDRESS#0x}"
owner_private_key = "${DEPLOYER_SECRET#0x}"
data_edge_address = "${data_edge#0x}"
epoch_manager_address = "${graph_epoch_manager#0x}"
subgraph_url = "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/block-oracle"
bearer_token = "TODO"
log_level = "trace"
# Default is 10 blocks — easy to trip under heavy test load when an
# anvil_mine burst (epoch advance, time travel) puts the chain hundreds of
# blocks ahead of the subgraph briefly, sending the service into a
# 2s-cooldown spiral. 100 keeps the check active for genuine stalls while
# absorbing typical test bursts.
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
exec /opt/block-oracle/block-oracle run config.toml
