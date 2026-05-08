#!/bin/sh
set -eu
# shellcheck source=/dev/null
. /opt/config/.env

# shellcheck source=/dev/null
. /opt/shared/lib.sh

# Per-indexer overrides. The primary indexer leaves these unset and inherits
# the default identity (RECEIVER_*) and service hostnames; extras inject their
# own values via compose `environment:`. Names match the indexer-agent and
# tap-agent run.sh files so a single set of overrides drives all three.
INDEXER_ADDRESS="${INDEXER_ADDRESS:-$RECEIVER_ADDRESS}"
INDEXER_OPERATOR_MNEMONIC="${INDEXER_OPERATOR_MNEMONIC:-$INDEXER_MNEMONIC}"
INDEXER_DB_NAME="${INDEXER_DB_NAME:-indexer_components_1}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
GRAPH_NODE_HOST="${GRAPH_NODE_HOST:-graph-node}"
PROTOCOL_GRAPH_NODE_HOST="${PROTOCOL_GRAPH_NODE_HOST:-graph-node}"

graph_tally_verifier=$(contract_addr GraphTallyCollector.address horizon)
subgraph_service=$(contract_addr SubgraphService.address subgraph-service)

# RecurringCollector gates the [dips] block. If the contract isn't deployed
# (older contracts branches, partial bring-up), we skip [dips] entirely so the
# binary still starts and serves TAP traffic. With it present, the indexer
# advertises pricing via /dips/info and accepts DIPs proposals.
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
free_query_auth_token = "freestuff"
host_and_port = "0.0.0.0:${INDEXER_SERVICE_PORT}"
url_prefix = "/"
serve_network_subgraph = false
serve_escrow_subgraph = false
# Without this, ipfs_url falls back to the public Graph IPFS gateway via
# default_values.toml in the indexer-rs config crate. The DIPs flow fetches
# subgraph manifests from IPFS to validate proposals — the public gateway
# can't serve manifests we only published to the local IPFS node, so DIPs
# proposals get rejected with SUBGRAPH_MANIFEST_UNAVAILABLE. Point at the
# stack's IPFS so the manifests resolve.
ipfs_url = "http://ipfs:${IPFS_RPC_PORT}"

[tap]
max_amount_willing_to_lose_grt = 1

[tap.rav_request]
timestamp_buffer_secs = 15

[tap.sender_aggregator_endpoints]
${ACCOUNT0_ADDRESS} = "http://graph-tally-aggregator:${GRAPH_TALLY_AGGREGATOR_PORT}"

EOF

# DIPs section is appended only when RecurringCollector is on-chain.
# Presence of [dips] makes indexer-service register the /dips/info HTTP route
# and the DIPs gRPC server on INDEXER_SERVICE_DIPS_RPC_PORT. IISA's scoring
# cronjob probes /dips/info to learn each indexer's supported networks and
# pricing floor; without it, IISA returns no candidates for any deployment.
if [ -n "$recurring_collector" ]; then
cat >>config.toml <<-EOF
[dips]
host = "0.0.0.0"
port = "${INDEXER_SERVICE_DIPS_RPC_PORT}"
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
