#!/usr/bin/env bash

set -e

########################################################################
# Configuration

export ORACLE_SOURCES=$NETWORK_SERVICES_SOURCES/availability-oracle
export ORACLE_SUBGRAPH=$NETWORK_SUBGRAPH_ENDPOINT
export ORACLE_IPFS=$IPFS
export ORACLE_CONTRACTS=$ETHEREUM_NETWORK
export ORACLE_ADDRESS=${ACCOUNT2_ADDRESS:2}
export ORACLE_SIGNING_KEY=${ACCOUNT2_KEY:2}

########################################################################
# Run

cd "$ORACLE_SOURCES"

cargo watch -x \
    "run -p availability-oracle -- \
      --ipfs-concurrency 4 \
      --ipfs-timeout 5000 \
      --min-signal 100 \
      --period 300" \
    | pino-pretty | tee /tmp/availability-oracle.log
