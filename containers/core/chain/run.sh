#!/bin/bash
set -eu

FORK_ARG=""
if [ -n "${FORK_RPC_URL:-}" ]; then
  echo "FORK_RPC_URL detected, starting anvil in fork mode"
  FORK_ARG="--fork-url $FORK_RPC_URL"
fi

# --preserve-historical-states: keep per-block state snapshots across the
# periodic --state dumps. Without it, anvil drops historical state on each
# dump and `eth_call`s at older blocks return BlockOutOfRangeError. Per-test
# graph-nodes deploy the network subgraph mid-run and need to index from
# block 0, which calls Controller.getGovernor() etc. at early blocks — those
# requests fail once the chain head has moved past the kept window.
exec anvil --host=0.0.0.0 --chain-id=1337 --base-fee=0 \
  --state /data/anvil-state.json \
  --preserve-historical-states \
  $FORK_ARG
