#!/bin/sh
set -eu
. /opt/.env

cd /opt
tap_verifier=$(jq -r '."1337".TAPVerifier.address' /opt/contracts.json)
cat >endpoints.yaml <<-EOF
${ACCOUNT0_ADDRESS}: "http://tap-aggregator:${TAP_AGGREGATOR}"
EOF
export ALLOCATION_SYNCING_INTERVAL_MS=10000
export ESCROW_SUBGRAPH_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/semiotic/tap"
export ESCROW_SYNCING_INTERVAL_MS=10000
export GRAPH_NODE_QUERY_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL}"
export GRAPH_NODE_STATUS_ENDPOINT="http://graph-node:${GRAPH_NODE_STATUS}/graphql"
export INDEXER_ADDRESS="${RECEIVER_ADDRESS}"
export LOG_LEVEL="info"
export NETWORK_SUBGRAPH_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network"
export POSTGRES_DATABASE="indexer_components_2"
export POSTGRES_HOST="postgres"
export POSTGRES_PASSWORD=""
export POSTGRES_PORT="${POSTGRES}"
export POSTGRES_USERNAME="postgres"
export RECEIPTS_VERIFIER_ADDRESS="${tap_verifier}"
export RECEIPTS_VERIFIER_CHAIN_ID=1337
export RAV_REQUEST_TRIGGER_VALUE=10
export SENDER_AGGREGATOR_ENDPOINTS="endpoints.yaml"
indexer-tap-agent
