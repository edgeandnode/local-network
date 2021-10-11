#!/usr/bin/env bash

set -e

########################################################################
# Configuration

export FISHERMAN_SOURCES=$NETWORK_SERVICES_SOURCES/fisherman
export FISHERMAN_TRUSTED_INDEXERS=${ACCOUNT_ADDRESS:2}@http://127.0.0.1:7600@superdupersecrettoken
export FISHERMAN_CONTRACTS=$ETHEREUM_NETWORK
export FISHERMAN_LOG_LEVEL=debug

########################################################################
# Run

cd "$FISHERMAN_SOURCES"

cargo watch -x \
    "run -p fisherman -- \
      --fisherman ${ACCOUNT1_ADDRESS:2} \
      --signing-key ${ACCOUNT1_KEY:2} \
      --trusted-indexers $FISHERMAN_TRUSTED_INDEXERS \
      --metrics-port 8041 \
      --server-port 1000" \
    | pino-pretty | tee /tmp/fisherman.log
