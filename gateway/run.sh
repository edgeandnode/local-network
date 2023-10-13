#!/bin/sh
set -euf

if [ ! -d "build/edgeandnode/graph-gateway" ]; then
  mkdir -p build/edgeandnode/graph-gateway
  git clone git@github.com:edgeandnode/graph-gateway build/edgeandnode/graph-gateway --branch 'v14.0.1'
fi

. ./.env
export HOST="${DOCKER_GATEWAY_HOST:-host.docker.internal}"

cd build/edgeandnode/graph-gateway

studio_admin_auth="$(curl "http://${HOST}:${CONTROLLER}/studio_admin_auth")"
echo "studio_admin_auth=${studio_admin_auth}"
export STUDIO_AUTH="${studio_admin_auth}"

envsubst <../../../gateway/config.jsonnet >config.jsonnet
jsonnet config.jsonnet >config.json
export RUST_LOG=info,graph_gateway=trace
cargo watch -x 'run --bin graph-gateway config.json'
