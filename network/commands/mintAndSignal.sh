#!/usr/bin/env bash

set -e

########################################################################
# Configuration

export ADDRESS_BOOK=$CONTRACTS_SOURCES/addresses.json
export GNS_CONTRACT_ADDRESS=$(jq '."1337".GNS.address' $ADDRESS_BOOK)

########################################################################
# Run

cd $CONTRACTS_SOURCES

# Approve GNS contract
./cli/cli.ts contracts graphToken approve \
  --mnemonic "$MNEMONIC" \
  --provider-url "$ETHEREUM" \
  --account "$GNS_CONTRACT_ADDRESS" \
  --amount 1000000

# Mint and signal on subgraph
./cli/cli.ts contracts gns mintNSignal \
  --graphAccount "$ACCOUNT_ADDRESS" \
  --tokens 1000 \
  --subgraphNumber 0
