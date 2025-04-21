#!/bin/sh
set -eu

FORK_ARG=""
if [ -n "${FORK_RPC_URL:-}" ]; then
  echo "FORK_RPC_URL detected, starting anvil in fork mode"
  FORK_ARG="--fork-url $FORK_RPC_URL"
fi

anvil --debug --host=0.0.0.0 --chain-id=1337 --base-fee=0 $FORK_ARG
