#!/bin/sh
set -eu
. /opt/config/.env

. /opt/shared/lib.sh

graph_tally_verifier=$(contract_addr GraphTallyCollector.address horizon)
subgraph_service=$(contract_addr SubgraphService.address subgraph-service)

cat >config.toml <<-EOF
[indexer]
indexer_address = "${INDEXER_ADDRESS}"
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

# Schema-required even in Horizon mode (where V2 escrow accounts live in the
# network subgraph itself). Point at the network subgraph as a satisfier; the
# legacy TAP v1 subgraph isn't deployed in this stack.
[subgraphs.escrow]
query_url = "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network"
syncing_interval_secs = 30

[blockchain]
chain_id = 1337
receipts_verifier_address_v2 = "${graph_tally_verifier}"
subgraph_service_address = "${subgraph_service}"

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
${DEPLOYER_ADDRESS} = "http://graph-tally-aggregator:${GRAPH_TALLY_AGGREGATOR_PORT}"

# Horizon mode. Required by the dips-fork build pinned in the
# indexing-payments overlay; a deprecated no-op on baseline v2.1.0+
# (upstream made Horizon always-on).
[horizon]
enabled = true
EOF

# DIPs config is only emitted when the indexing-payments overlay is active —
# the upstream indexer-rs build pinned in services.env doesn't recognise the
# [dips] schema. The indexing-payments.env overlay sets INDEXING_PAYMENTS_ENABLED=1
# and bumps INDEXER_SERVICE_RS_VERSION to a dips-fork sha that does.
if [ "${INDEXING_PAYMENTS_ENABLED:-0}" = "1" ]; then
  recurring_collector=$(contract_addr RecurringCollector.address horizon)
  cat >>config.toml <<-EOF

	[dips]
	host = "0.0.0.0"
	port = "${INDEXER_SERVICE_DIPS_PORT}"
	recurring_collector = "${recurring_collector}"
	supported_networks = ["hardhat"]
	min_grt_per_billion_entities_per_30_days = "0"

	[dips.min_grt_per_30_days]
	hardhat = "0"

	[dips.additional_networks]
	hardhat = "1337"

	[subgraphs.indexing_payments]
	query_url = "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/indexing-payments"
	syncing_interval_secs = 60
	EOF
fi
cat config.toml

indexer-service-rs --config=config.toml
