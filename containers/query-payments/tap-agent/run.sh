#!/bin/sh
set -eu
# shellcheck source=/dev/null
. /opt/config/.env

# shellcheck source=/dev/null
. /opt/shared/lib.sh

# Allow env var overrides for multi-indexer support
INDEXER_ADDRESS="${INDEXER_ADDRESS:-$RECEIVER_ADDRESS}"
INDEXER_OPERATOR_MNEMONIC="${INDEXER_OPERATOR_MNEMONIC:-$INDEXER_MNEMONIC}"
INDEXER_DB_NAME="${INDEXER_DB_NAME:-indexer_components_1}"
GRAPH_NODE_HOST="${GRAPH_NODE_HOST:-graph-node}"
PROTOCOL_GRAPH_NODE_HOST="${PROTOCOL_GRAPH_NODE_HOST:-graph-node}"
POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"

wait_for_rpc

cd /opt
graph_tally_verifier=$(contract_addr GraphTallyCollector.address horizon)
subgraph_service=$(contract_addr SubgraphService.address subgraph-service)

cat >endpoints.yaml <<-EOF
${ACCOUNT0_ADDRESS}: "http://graph-tally-aggregator:${GRAPH_TALLY_AGGREGATOR_PORT}"
EOF

cat >config.toml <<-EOF
[indexer]
indexer_address = "${INDEXER_ADDRESS}"
operator_mnemonic = "${INDEXER_OPERATOR_MNEMONIC}"

[database]
postgres_url = "postgresql://postgres@${POSTGRES_HOST}:${POSTGRES_PORT}/${INDEXER_DB_NAME}"

[graph_node]
query_url = "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}"
status_url = "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_STATUS_PORT}/graphql"

[subgraphs.network]
query_url = "http://${PROTOCOL_GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network"
recently_closed_allocation_buffer_secs = 60
syncing_interval_secs = 30

# The escrow subgraph (legacy semiotic/tap) is not deployed on this branch;
# TAP signer authorizations live in Horizon contracts. The binary still
# requires this section as a hard-required TOML field. Stale URL satisfies
# the schema; queries against it fail gracefully and the DIPs flow does not
# exercise this path.
[subgraphs.escrow]
query_url = "http://${PROTOCOL_GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/semiotic/tap"
syncing_interval_secs = 30

[blockchain]
chain_id = 1337
receipts_verifier_address_v2 = "${graph_tally_verifier}"
subgraph_service_address = "${subgraph_service}"

[service]
host_and_port = "0.0.0.0:${INDEXER_SERVICE_PORT}"
url_prefix = "/"
serve_network_subgraph = false
serve_escrow_subgraph = false

[tap]
max_amount_willing_to_lose_grt = 1

[tap.rav_request]
timestamp_buffer_secs = 15

[tap.sender_aggregator_endpoints]
${ACCOUNT0_ADDRESS} = "http://graph-tally-aggregator:${GRAPH_TALLY_AGGREGATOR_PORT}"

EOF
cat config.toml

indexer-tap-agent --config=config.toml
