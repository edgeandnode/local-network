#!/bin/sh
set -eu
. /opt/.env

cd /opt
tap_verifier=$(jq -r '."1337".TAPVerifier.address' /opt/contracts.json)
cat >endpoints.yaml <<-EOF
${ACCOUNT0_ADDRESS}: "http://tap-aggregator:${TAP_AGGREGATOR}"
EOF

cat >config.toml <<-EOF
[ethereum]
indexer_address = "${RECEIVER_ADDRESS}"

[receipts]
receipts_verifier_chain_id = 1337
receipts_verifier_address = "${tap_verifier}"

[indexer_infrastructure]
graph_node_query_endpoint = "http://graph-node:${GRAPH_NODE_GRAPHQL}"
graph_node_status_endpoint = "http://graph-node:${GRAPH_NODE_STATUS}/graphql"
log_level = "info"

[postgres]
postgres_host = "postgres"
postgres_database = "indexer_components_1"
postgres_username = "postgres"
postgres_password = ""
postgres_port = ${POSTGRES}

[network_subgraph]
allocation_syncing_interval_ms = 10000
network_subgraph_endpoint = "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network"

[escrow_subgraph]
escrow_subgraph_endpoint = "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/semiotic/tap"
escrow_syncing_interval_ms = 10000

[tap]
rav_request_trigger_value = 100
sender_aggregator_endpoints_file = "endpoints.yaml"
EOF
cat config.toml

indexer-tap-agent --config=config.toml
