#!/bin/sh
set -eu
. /opt/.env

cd gateway
export $(cat /opt/.env | sed 's/^#.*$//g' | xargs)
export DISPUTE_MANAGER="$(jq -r '."1337".DisputeManager.address' /opt/contracts.json)"
envsubst </opt/config.json >config.json
cat config.json

export RUST_LOG=info,gateway_framework=trace,graph_gateway=trace
./target/debug/graph-gateway ./config.json
