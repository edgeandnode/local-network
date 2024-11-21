#!/bin/sh
set -eu
. /opt/.env

tap_verifier=$(jq -r '."1337".TAPVerifier.address' /opt/contracts.json)

cat >config.toml <<-EOF
[indexer]
indexer_address = "${RECEIVER_ADDRESS}"
operator_mnemonic = "${INDEXER_MNEMONIC}"

[database]
postgres_url = "postgresql://postgres@host.docker.internal:${POSTGRES}/indexer_components_1"

[graph_node]
query_url = "http://host.docker.internal:${GRAPH_NODE_GRAPHQL}"
status_url = "http://host.docker.internal:${GRAPH_NODE_STATUS}/graphql"

[subgraphs.network]
query_url = "http://host.docker.internal:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network"
recently_closed_allocation_buffer_secs = 60
syncing_interval_secs = 30

[subgraphs.escrow]
query_url = "http://host.docker.internal:${GRAPH_NODE_GRAPHQL}/subgraphs/name/semiotic/tap"
syncing_interval_secs = 30

[blockchain]
chain_id = 1337
receipts_verifier_address = "${tap_verifier}"

[service]
host_and_port = "0.0.0.0:${INDEXER_SERVICE}"
free_query_auth_token = "freestuff"
url_prefix = "/"
serve_network_subgraph = false
serve_escrow_subgraph = false
[tap]
max_amount_willing_to_lose_grt = 1000
[tap.rav_request]
timestamp_buffer_secs = 1000
[tap.sender_aggregator_endpoints]
${ACCOUNT0_ADDRESS} = "http://host.docker.internal:${TAP_AGGREGATOR}"

EOF
cat config.toml

export RUST_LOG="info,service=debug"

indexer-service-rs --config=config.toml
