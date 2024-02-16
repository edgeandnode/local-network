#!/bin/sh
set -eufx

if [ ! -d "build/graphprotocol/indexer-rs" ]; then
  mkdir -p build/graphprotocol/indexer-rs
  git clone git@github.com:graphprotocol/indexer-rs build/graphprotocol/indexer-rs --branch main
fi

. ./.env

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


echo "awaiting controller"
dynamic_host_setup controller
until curl -s "http://${CONTROLLER_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done

echo "awaiting postgres"
dynamic_host_setup postgres
until curl -s "http://${POSTGRES_HOST}:${POSTGRES}"; [ $? = 52 ]; do sleep 1; done

echo "awaiting network subgraph"
network_subgraph="$(curl "http://${CONTROLLER_HOST}:${CONTROLLER}/graph_subgraph")"
echo "network_subgraph=${network_subgraph}"

echo "awaiting escrow subgraph"
escrow_subgraph="$(curl "http://${CONTROLLER_HOST}:${CONTROLLER}/escrow_subgraph")"
echo "escrow_subgraph=${escrow_subgraph}"

echo "awaiting scalar-tap-contracts"
curl "http://${CONTROLLER_HOST}:${CONTROLLER}/scalar_tap_contracts" >scalar_tap_contracts.json

dynamic_host_setup indexer-agent
echo "awaiting indexer-agent"
until curl -s "http://${INDEXER_AGENT_HOST}:${INDEXER_MANAGEMENT}" >/dev/null; do sleep 1; done

tap_verifier=$(cat scalar_tap_contracts.json | jq -r '."1337".TAPVerifier')
echo "tap_verifier=${tap_verifier}"

dynamic_host_setup graph-node

cd build/graphprotocol/indexer-rs
cat <<-EOT > config.toml
[common.indexer]
indexer_address = "${ACCOUNT0_ADDRESS}"
operator_mnemonic = "${MNEMONIC}"

[common.graph_node]
status_url = "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_STATUS}/graphql"
query_base_url = "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL}"

[common.database]
postgres_url = "postgresql://dev@${POSTGRES_HOST}:${POSTGRES}/indexer_components_0"

[common.network_subgraph]
query_url = "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL}/subgraphs/id/${network_subgraph}"
syncing_interval = 10

[common.escrow_subgraph]
query_url = "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL}/subgraphs/id/${escrow_subgraph}"
syncing_interval = 60

[common.graph_network]
chain_id = 1337
id = 1

[common.server]
url_prefix = "/"
host_and_port = "0.0.0.0:${INDEXER_SERVICE}"
metrics_host_and_port = "0.0.0.0:${INDEXER_SERVICE_METRICS}"
free_query_auth_token = "foo"

[common.scalar]
chain_id = 1337
receipts_verifier_address = "${tap_verifier}"
EOT

cat config.toml

if [ ! -f "./indexer-service" ]; then
  cargo build -p service
  cp target/debug/service ./indexer-service
fi

export RUST_LOG=debug
./indexer-service --config config.toml

# cargo run -p service -- --config config.toml
