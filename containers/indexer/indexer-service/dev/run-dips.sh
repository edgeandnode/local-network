#!/bin/bash
set -eu

. /opt/config/.env
. /opt/shared/lib.sh

tap_verifier=$(contract_addr TAPVerifier tap-contracts)
graph_tally_verifier=$(contract_addr GraphTallyCollector.address horizon)
subgraph_service=$(contract_addr SubgraphService.address subgraph-service)

# RecurringCollector may not be deployed yet (contracts repo work pending)
recurring_collector=$(contract_addr RecurringCollector.address horizon 2>/dev/null) || recurring_collector=""
if [ -z "$recurring_collector" ]; then
  echo "WARNING: RecurringCollector not deployed - DIPs will be disabled"
  dips_enabled=false
else
  dips_enabled=true
fi

cat >/opt/config.toml <<-EOF
[indexer]
indexer_address = "${RECEIVER_ADDRESS}"
operator_mnemonic = "${INDEXER_MNEMONIC}"

[database]
postgres_url = "postgresql://postgres@postgres:${POSTGRES_PORT}/indexer_components_1"

[graph_node]
query_url = "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}"
status_url = "http://graph-node:${GRAPH_NODE_STATUS_PORT}/graphql"

[subgraphs.network]
query_url = "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network"
recently_closed_allocation_buffer_secs = 60
syncing_interval_secs = 30

[subgraphs.escrow]
query_url = "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/semiotic/tap"
syncing_interval_secs = 30

[blockchain]
chain_id = ${CHAIN_ID}
receipts_verifier_address = "${tap_verifier}"
receipts_verifier_address_v2 = "${graph_tally_verifier}"
subgraph_service_address = "${subgraph_service}"

[service]
free_query_auth_token = "freestuff"
host_and_port = "0.0.0.0:${INDEXER_SERVICE_PORT}"
url_prefix = "/"
serve_network_subgraph = false
serve_escrow_subgraph = false
ipfs_url = "http://ipfs:${IPFS_RPC_PORT}"

[tap]
max_amount_willing_to_lose_grt = 1

[tap.rav_request]
timestamp_buffer_secs = 15

[tap.sender_aggregator_endpoints]
${ACCOUNT0_ADDRESS} = "http://tap-aggregator:${TAP_AGGREGATOR_PORT}"

[horizon]
enabled = true
EOF

if [ "$dips_enabled" = "true" ]; then
cat >>/opt/config.toml <<-EOF

[dips]
host = "0.0.0.0"
port = "${INDEXER_SERVICE_DIPS_RPC_PORT}"
recurring_collector = "${recurring_collector}"
supported_networks = ["hardhat"]

[dips.min_grt_per_30_days]
"hardhat" = "450"

[dips.additional_networks]
"hardhat" = "eip155:1337"
EOF
fi
cat /opt/config.toml

cd /opt/source
cargo build --bin indexer-service-rs
exec ./target/debug/indexer-service-rs --config=/opt/config.toml
