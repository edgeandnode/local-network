#!/bin/sh
set -eu
# shellcheck source=/dev/null
. /opt/config/.env

# shellcheck source=/dev/null
. /opt/shared/lib.sh

# Per-indexer overrides. The primary leaves these unset and inherits the default
# identity (RECEIVER_*) and hostnames; extras inject their own via compose env.
# Names match the indexer-agent/tap-agent run.sh so one set drives all three.
INDEXER_ADDRESS="${INDEXER_ADDRESS:-$RECEIVER_ADDRESS}"
INDEXER_OPERATOR_MNEMONIC="${INDEXER_OPERATOR_MNEMONIC:-$INDEXER_MNEMONIC}"
INDEXER_DB_NAME="${INDEXER_DB_NAME:-indexer_components_1}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
GRAPH_NODE_HOST="${GRAPH_NODE_HOST:-graph-node}"
PROTOCOL_GRAPH_NODE_HOST="${PROTOCOL_GRAPH_NODE_HOST:-graph-node}"

graph_tally_verifier=$(contract_addr GraphTallyCollector.address horizon)
subgraph_service=$(contract_addr SubgraphService.address subgraph-service)

# RecurringCollector gates the [dips] block. Without the contract (older
# branches, partial bring-up) we skip [dips] so the binary still serves TAP;
# with it, the indexer advertises pricing via /dips/info and accepts proposals.
recurring_collector=$(contract_addr RecurringCollector.address horizon 2>/dev/null) || recurring_collector=""

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

# The legacy escrow subgraph isn't deployed here (TAP authorizations live in
# Horizon contracts), but the binary still requires this section. The stale URL
# satisfies the schema; queries fail gracefully and DIPs never exercises it.
[subgraphs.escrow]
query_url = "http://${PROTOCOL_GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/semiotic/tap"
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
# Point at the stack's IPFS: DIPs fetches subgraph manifests from IPFS to
# validate proposals, and the default public gateway can't serve manifests we
# only published locally, so proposals fail with SUBGRAPH_MANIFEST_UNAVAILABLE.
ipfs_url = "http://ipfs:${IPFS_RPC_PORT}"

[tap]
max_amount_willing_to_lose_grt = 1

[tap.rav_request]
timestamp_buffer_secs = 15

[tap.sender_aggregator_endpoints]
${ACCOUNT0_ADDRESS} = "http://graph-tally-aggregator:${GRAPH_TALLY_AGGREGATOR_PORT}"

EOF

# Appended only when RecurringCollector is on-chain. [dips] registers the
# /dips/info route and the DIPs gRPC server on the fixed port 7602 the payer
# dials; IISA probes /dips/info for networks and pricing, else no candidates.
if [ -n "$recurring_collector" ]; then
cat >>config.toml <<-EOF
[subgraphs.indexing_payments]
query_url = "http://${PROTOCOL_GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/indexing-payments"
syncing_interval_secs = 30

[dips]
host = "0.0.0.0"
recurring_collector = "${recurring_collector}"
supported_networks = ["hardhat"]
min_grt_per_billion_entities_per_30_days = "${DIPS_MIN_GRT_PER_BILLION_ENTITIES_PER_30_DAYS}"

[dips.min_grt_per_30_days]
"hardhat" = "${DIPS_MIN_GRT_PER_30_DAYS}"

[dips.additional_networks]
"hardhat" = "eip155:1337"
EOF
else
  echo "WARNING: RecurringCollector not in horizon.json — DIPs disabled (TAP-only mode)"
fi

cat config.toml

indexer-service-rs --config=config.toml
