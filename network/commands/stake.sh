#!/usr/bin/env bash

set -e

########################################################################
# Configuration

export ADDRESS_BOOK=$CONTRACTS_SOURCES/addresses.json
export STAKING_CONTRACT_ADDRESS=$(jq '."1337".Staking.address' $ADDRESS_BOOK)

########################################################################
# Run

cd $CONTRACTS_SOURCES

# Approve staking contract
./cli/cli.ts contracts graphToken approve \
  --mnemonic "$MNEMONIC" \
  --provider-url "$ETHEREUM" \
  --account "$STAKING_CONTRACT_ADDRESS" \
  --amount 1000000

# Stake
./cli/cli.ts contracts staking stake \
  --mnemonic "$MNEMONIC" \
  --provider-url "$ETHEREUM" \
  --amount 1000000
