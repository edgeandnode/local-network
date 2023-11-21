#!/bin/sh
set -eufx

if [ ! -d "build/graphprotocol/indexer-rs" ]; then
  mkdir -p build/graphprotocol/indexer-rs
  git clone git@github.com:graphprotocol/indexer-rs build/graphprotocol/indexer-rs --branch jannis/subgraph-service
fi

. ./.env

echo "awaiting controller"
until curl -s "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done

echo "awaiting postgres"
until curl -s "http://${DOCKER_GATEWAY_HOST}:${POSTGRES}"; [ $? = 52 ]; do sleep 1; done

host="${DOCKER_GATEWAY_HOST:-host.docker.internal}"
echo "host=${host}"

network_subgraph="$(curl "http://${host}:${CONTROLLER}/graph_subgraph")"
echo "network_subgraph=${network_subgraph}"

escrow_subgraph="$(curl "http://${host}:${CONTROLLER}/escrow_subgraph")"
echo "escrow_subgraph=${escrow_subgraph}"

cd build/graphprotocol/indexer-rs
cat <<-EOT > config.toml
[common.indexer]
indexer_address = "${ACCOUNT0_ADDRESS}"
operator_mnemonic = "${MNEMONIC}"

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
url_prefix = "/subgraphs"
host_and_port = "0.0.0.0:${INDEXER_SERVICE}"
metrics_host_and_port = "0.0.0.0:${INDEXER_SERVICE_METRICS}"
EOT

cat config.toml

cargo run -p service -- --config config.toml