#!/bin/sh
set -euf

if [ ! -d "build/edgeandnode/graph-gateway" ]; then
  mkdir -p build/edgeandnode/graph-gateway
  git clone git@github.com:edgeandnode/graph-gateway build/edgeandnode/graph-gateway --branch 'main'
fi

. ./.env

echo "awaiting graph_subgraph"
until curl -s "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/graph_subgraph" >/dev/null; do sleep 1; done
echo "awaiting allocation_subgraph"
until curl -s "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/allocation_subgraph" >/dev/null; do sleep 1; done
echo "awaiting block_oracle"
until curl -s "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/block_oracle_subgraph" >/dev/null; do sleep 1; done

cd build/edgeandnode/graph-gateway

echo "awaiting graph_contracts"
dispute_manager="$(curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/graph_contracts" | jq -r '."1337".DisputeManager.address')"
echo "dispute_manager=${dispute_manager}"
export DISPUTE_MANAGER="${dispute_manager}"

echo "awaiting studio_admin_auth"
studio_admin_auth="$(curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/studio_admin_auth")"
echo "studio_admin_auth=${studio_admin_auth}"
export STUDIO_AUTH="${studio_admin_auth}"

export GATEWAY_SIGNER=${ACCOUNT1_SECRET_KEY}
echo "GATEWAY_SIGNER=${GATEWAY_SIGNER}"

envsubst <../../../gateway/config.jsonnet >config.jsonnet
jsonnet config.jsonnet >config.json
export RUST_LOG=info,graph_gateway=trace,graph_gateway::chains=debug
cargo watch -x 'run --bin graph-gateway config.json'
