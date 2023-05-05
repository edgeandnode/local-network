#!/bin/bash
. ./prelude.sh

github_clone edgeandnode/network-services main
cd build/edgeandnode/network-services
cargo build
cd -

await_ready graph-subgraph

export FISHERMAN_CONTRACTS="${PWD}/build/graphprotocol/contracts/addresses.json"

cd build/edgeandnode/network-services

export FISHERMAN_TRUSTED_INDEXERS="${ACCOUNT_ADDRESS:2}@http://127.0.0.1:${INDEXER_SERVICE_PORT}@superdupersecrettoken"
export FISHERMAN_PROVIDER_URL="http://127.0.0.1:${ETHEREUM_PORT}"
export FISHERMAN_CHAIN="${ETHEREUM_NETWORK_ID}"

cargo run --bin fisherman -- \
  --fisherman "${ACCOUNT1_ADDRESS:2}" \
  --signing-key "${ACCOUNT1_KEY:2}" \
  --metrics-port 8041 \
  --server-port "${FISHERMAN_PORT}" \
  2>&1| pino-pretty | tee /tmp/local-net/fisherman.log
