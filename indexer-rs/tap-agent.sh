#!/bin/sh
set -eufx

if [ ! -d "build/graphprotocol/indexer-rs" ]; then
  mkdir -p build/graphprotocol/indexer-rs
  git clone git@github.com:graphprotocol/indexer-rs build/graphprotocol/indexer-rs --branch main
fi

. ./.env

host="${DOCKER_GATEWAY_HOST:-host.docker.internal}"
echo "host=${host}"

echo "awaiting controller"
until curl -s "http://${host}:${CONTROLLER}" >/dev/null; do sleep 1; done

echo "awaiting postgres"
until curl -s "http://${host}:${POSTGRES}"; [ $? = 52 ]; do sleep 1; done

echo "awaiting network subgraph"
network_subgraph="$(curl "http://${host}:${CONTROLLER}/graph_subgraph")"
echo "network_subgraph=${network_subgraph}"

echo "awaiting escrow subgraph"
escrow_subgraph="$(curl "http://${host}:${CONTROLLER}/escrow_subgraph")"
echo "escrow_subgraph=${escrow_subgraph}"

echo "awaiting scalar-tap-contracts"
curl "http://${host}:${CONTROLLER}/scalar_tap_contracts" >scalar_tap_contracts.json

tap_verifier=$(cat scalar_tap_contracts.json | jq -r '.tap_verifier')
echo "tap_verifier=${tap_verifier}"

cd build/graphprotocol/indexer-rs
cat <<-EOT > config.toml
[ethereum]
indexer_address = "${ACCOUNT0_ADDRESS}"

[receipts]
receipts_verifier_chain_id = 1337
receipts_verifier_address = "${tap_verifier}"

[indexer_infrastructure]
metrics_port = 7300
graph_node_query_endpoint = "http://${host}:${GRAPH_NODE_GRAPHQL}"
graph_node_status_endpoint = "http://${host}:${GRAPH_NODE_STATUS}/graphql"
log_lever = "info"

[postgres]
postgres_host = "${host}"
postgres_port = ${POSTGRES}
postgres_database = "indexer_components_0"
postgres_username = "dev"
postgres_password = ""

[network_subgraph]
network_subgraph_deployment = "${network_subgraph}"
network_subgraph_endpoint = "http://${host}:${GRAPH_NODE_GRAPHQL}/subgraphs/id/${network_subgraph}"
allocation_syncing_interval_ms = 60000

[escrow_subgraph]
escrow_subgraph_deployment = "${escrow_subgraph}"
escrow_subgraph_endpoint = "http://${host}:${GRAPH_NODE_GRAPHQL}/subgraphs/id/${escrow_subgraph}"
escrow_syncing_interval_ms = 60000

[tap]
rav_request_trigger_value = 1
rav_request_timestamp_buffer_ms = 1000
rav_request_timeout_secs = 5
sender_aggregator_endpoints_file = "endpoints.yaml"
EOT

cat config.toml

cat <<-EOT > endpoints.yaml
${GATEWAY_SENDER_ADDRESS}: "http://${host}:${TAP_AGGREGATOR}"
EOT

export RUST_LOG=debug
# config=config.toml cargo run -p indexer-tap-agent
