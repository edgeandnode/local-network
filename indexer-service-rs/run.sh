#!/bin/sh
set -eu
. /opt/.env

tap_verifier=$(jq -r '."1337".TAPVerifier.address' /opt/contracts.json)

network_subgraph_deployment=$(curl "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network" \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { deployment } }" }' \
  | jq -r '.data._meta.deployment')
escrow_deployment=$(curl "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/semiotic/tap" \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { deployment } }" }' \
  | jq -r '.data._meta.deployment')

cat >config.toml <<-EOF
[common.indexer]
indexer_address = "${RECEIVER_ADDRESS}"
operator_mnemonic = "${INDEXER_MNEMONIC}"

[common.server]
host_and_port = "0.0.0.0:${INDEXER_SERVICE_RS}"
url_prefix = "/"

[common.database]
postgres_url = "postgresql://postgres@postgres:${POSTGRES}/indexer_components_1"

[common.graph_node]
query_base_url = "http://graph-node:${GRAPH_NODE_GRAPHQL}"
status_url = "http://graph-node:${GRAPH_NODE_STATUS}/graphql"

[common.network_subgraph]
deployment = "${network_subgraph_deployment}"
query_url = "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network"
recently_closed_allocation_buffer_seconds = 60
serve_subgraph = true
syncing_interval = 30

[common.escrow_subgraph]
deployment = "${escrow_deployment}"
query_url = "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/semiotic/tap"
serve_subgraph = true
syncing_interval = 30

[common.graph_network]
id = 1
chain_id = 1337

[common.scalar]
chain_id = 1337
receipts_verifier_address = "${tap_verifier}"
timestamp_error_tolerance = 30
EOF
cat config.toml

export RUST_LOG="info,service=debug"

service --config=config.toml
