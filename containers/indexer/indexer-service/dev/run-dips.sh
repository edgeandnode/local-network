#!/bin/bash
set -eu

. /opt/config/.env
. /opt/shared/lib.sh

# Allow env var overrides for multi-indexer support
INDEXER_ADDRESS="${INDEXER_ADDRESS:-$RECEIVER_ADDRESS}"
INDEXER_OPERATOR_MNEMONIC="${INDEXER_OPERATOR_MNEMONIC:-$INDEXER_MNEMONIC}"
INDEXER_DB_NAME="${INDEXER_DB_NAME:-indexer_components_1}"
GRAPH_NODE_HOST="${GRAPH_NODE_HOST:-graph-node}"
PROTOCOL_GRAPH_NODE_HOST="${PROTOCOL_GRAPH_NODE_HOST:-graph-node}"
POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
DIPS_MIN_GRT_PER_30_DAYS="${DIPS_MIN_GRT_PER_30_DAYS:-450}"

# --- Start cargo build immediately (no deps needed) ---
(
  cd /opt/source
  flock -x 200
  if [ ! -f ./target/debug/indexer-service-rs ]; then
    cargo build --bin indexer-service-rs
  fi
) 200>/opt/source/.cargo-build.lock &
BUILD_PID=$!

# --- Wait for dependencies in parallel with build ---
wait_for_config
wait_for_rpc

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

[subgraphs.escrow]
query_url = "http://${PROTOCOL_GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/semiotic/tap"
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
indexing_payments_subgraph_url = "http://${PROTOCOL_GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graphprotocol/indexing-payments"

[dips.min_grt_per_30_days]
"hardhat" = "${DIPS_MIN_GRT_PER_30_DAYS}"

[dips.additional_networks]
"hardhat" = "eip155:1337"
EOF
fi
cat /opt/config.toml

# --- Wait for build to finish ---
echo "Waiting for cargo build to complete..."
wait $BUILD_PID
echo "Build complete"

# --- Wait for runtime deps before launching ---
wait_for_url "http://indexer-agent:${INDEXER_MANAGEMENT_PORT}" 600
echo "Waiting for network subgraph..." >&2
wait_for_gql \
  "http://${PROTOCOL_GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network" \
  "{ _meta { deployment } }" \
  ".data._meta.deployment" \
  600

exec /opt/source/target/debug/indexer-service-rs --config=/opt/config.toml
