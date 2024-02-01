#!/bin/sh
set -eufx

if [ ! -d "build/graphprotocol/indexer-rs" ]; then
  mkdir -p build/graphprotocol/indexer-rs
  git clone git@github.com:graphprotocol/indexer-rs build/graphprotocol/indexer-rs --branch main
fi

. ./.env
if ! grep -q docker /proc/1/cgroup; then 
  export DOCKER_GATEWAY_HOST=127.0.0.1
fi



dynamic_host_setup() {
    if [ $# -eq 0 ]; then
        echo "No name provided."
        return 1
    fi

    # Convert the name to uppercase for the variable name
    local name_upper=$(echo $1 | tr '-' '_' | tr '[:lower:]' '[:upper:]')
    local export_name="${name_upper}_HOST"
    local host_name="$1"

    # Directly use 'eval' for dynamic variable assignment to avoid bad substitution
    eval export ${export_name}="${host_name}"
    if ! getent hosts "${host_name}" >/dev/null; then
        eval export ${export_name}="\$DOCKER_GATEWAY_HOST"
    fi

    # Use 'eval' for echoing dynamic variable value
    eval echo "${export_name} is set to \$${export_name}"
}

dynamic_host_setup controller
dynamic_host_setup postgres
dynamic_host_setup graph-node
dynamic_host_setup tap-aggregator

echo "awaiting controller"
until curl -s "http://${CONTROLLER_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done

echo "awaiting postgres"
until curl -s "http://${POSTGRES_HOST}:${POSTGRES}"; [ $? = 52 ]; do sleep 1; done

echo "awaiting network subgraph"
network_subgraph="$(curl "http://${CONTROLLER_HOST}:${CONTROLLER}/graph_subgraph")"
echo "network_subgraph=${network_subgraph}"

echo "awaiting escrow subgraph"
escrow_subgraph="$(curl "http://${CONTROLLER_HOST}:${CONTROLLER}/escrow_subgraph")"
echo "escrow_subgraph=${escrow_subgraph}"

echo "awaiting allocation_subgraph"
until curl -s "http://${CONTROLLER_HOST}:${CONTROLLER}/allocation_subgraph" >/dev/null; do sleep 1; done

echo "awaiting scalar-tap-contracts"
curl "http://${CONTROLLER_HOST}:${CONTROLLER}/scalar_tap_contracts" >scalar_tap_contracts.json

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
graph_node_query_endpoint = "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL}"
graph_node_status_endpoint = "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_STATUS}/graphql"
log_level = "info"

[postgres]
postgres_host = "${POSTGRES_HOST}"
postgres_port = ${POSTGRES}
postgres_database = "indexer_components_0"
postgres_username = "dev"
postgres_password = ""

[network_subgraph]
network_subgraph_deployment = "${network_subgraph}"
network_subgraph_endpoint = "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL}/subgraphs/id/${network_subgraph}"
allocation_syncing_interval_ms = 60000

[escrow_subgraph]
escrow_subgraph_deployment = "${escrow_subgraph}"
escrow_subgraph_endpoint = "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL}/subgraphs/id/${escrow_subgraph}"
escrow_syncing_interval_ms = 60000

[tap]
rav_request_trigger_value = 1
rav_request_timestamp_buffer_ms = 1000
rav_request_timeout_secs = 5
sender_aggregator_endpoints_file = "endpoints.yaml"
EOT

cat config.toml

cat <<-EOT > endpoints.yaml
${GATEWAY_SENDER_ADDRESS}: "http://${TAP_AGGREGATOR_HOST}:${TAP_AGGREGATOR}"
EOT

export RUST_LOG=debug
config=config.toml cargo run -p indexer-tap-agent -- --config config.toml
