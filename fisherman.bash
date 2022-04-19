#!/bin/bash
. ./prelude.sh

github_clone edgeandnode/network-services master
cd build/edgeandnode/network-services
cargo build
cd -

await_ready graph-subgraph

cd build/edgeandnode/network-services

export FISHERMAN_TRUSTED_INDEXERS="${ACCOUNT_ADDRESS:2}@http://127.0.0.1:${INDEXER_SERVICE_PORT}@superdupersecrettoken"
export FISHERMAN_CONTRACTS=ganache/mainnet
export FISHERMAN_LOG_LEVEL=debug

cargo run --bin fisherman -- \
  --fisherman "${ACCOUNT1_ADDRESS:2}" \
  --signing-key "${ACCOUNT1_KEY:2}" \
  --trusted-indexers "${FISHERMAN_TRUSTED_INDEXERS}" \
  --metrics-port 8041 \
  --server-port 11000 \
  2>&1| pino-pretty | tee /tmp/fisherman.log
