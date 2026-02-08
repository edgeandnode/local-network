#!/bin/sh
set -eu
. /opt/config/.env

. /opt/shared/lib.sh

tap_verifier=$(contract_addr TAPVerifier tap-contracts)
graph_tally_verifier=$(contract_addr GraphTallyCollector.address horizon)
subgraph_service=$(contract_addr SubgraphService.address subgraph-service)

cat >config.toml <<-EOF
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
chain_id = 1337
receipts_verifier_address = "${tap_verifier}"
receipts_verifier_address_v2 = "${graph_tally_verifier}"
subgraph_service_address= "${subgraph_service}"

[service]
free_query_auth_token = "freestuff"
host_and_port = "0.0.0.0:${INDEXER_SERVICE_PORT}"
url_prefix = "/"
serve_network_subgraph = false
serve_escrow_subgraph = false

[tap]
max_amount_willing_to_lose_grt = 1

[tap.rav_request]
timestamp_buffer_secs = 15

[tap.sender_aggregator_endpoints]
${ACCOUNT0_ADDRESS} = "http://tap-aggregator:${TAP_AGGREGATOR_PORT}"

[horizon]
# Enable Horizon migration support and detection
# When enabled: Check if Horizon contracts are active in the network
#   - If Horizon contracts detected: Hybrid migration mode (new V2 receipts only, process existing V1 receipts)
#   - If Horizon contracts not detected: Remain in legacy mode (V1 receipts only)
# When disabled: Pure legacy mode, no Horizon detection performed
enabled = true
EOF
cat config.toml

indexer-service-rs --config=config.toml
