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
[common.indexer]
indexer_address = "${ACCOUNT0_ADDRESS}"
operator_mnemonic = "${MNEMONIC}"

[common.graph_node]
status_url = "http://${host}:${GRAPH_NODE_STATUS}/graphql"
query_base_url = "http://${host}:${GRAPH_NODE_GRAPHQL}"

[common.database]
postgres_url = "postgresql://dev@${host}:${POSTGRES}/indexer_components_0"

[common.network_subgraph]
query_url = "http://${host}:${GRAPH_NODE_GRAPHQL}/subgraphs/id/${network_subgraph}"
syncing_interval = 60

[common.escrow_subgraph]
query_url = "http://${host}:${GRAPH_NODE_GRAPHQL}/subgraphs/id/${escrow_subgraph}"
syncing_interval = 60

[common.graph_network]
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

# Run migrations to ensure scalar TAP relations exist
sqlx migrate run --database-url "postgresql://dev@${host}:${POSTGRES}/indexer_components_0"

cargo run -p service -- --config config.toml
