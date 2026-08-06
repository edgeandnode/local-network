#!/bin/bash
set -eu

FORK_ARG=()
if [ -n "${FORK_RPC_URL:-}" ]; then
  echo "FORK_RPC_URL detected, starting anvil in fork mode"
  FORK_ARG=(--fork-url "$FORK_RPC_URL")
fi

# 20 accounts (anvil defaults to 10) so the junk-mnemonic accounts used by extra
# indexers (indices 2-19, see scripts/gen-extra-indexers.py) are pre-funded with ETH.
exec anvil --host=0.0.0.0 --chain-id=1337 --base-fee=0 \
  --state /data/anvil-state.json \
  --accounts 20 \
  --disable-code-size-limit \
  --hardfork cancun \
  "${FORK_ARG[@]}"
