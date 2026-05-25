#!/bin/bash

# Fund a wallet address with ETH on the local Hardhat chain.
# Usage: fund-wallet.sh <address> [amount_in_eth]

set -euo pipefail

source "$(dirname "$0")/../.env"
CHAIN_HOST="${CHAIN_HOST:-localhost}"

ADDRESS="${1:-}"
AMOUNT_ETH="${2:-1}"

if [[ -z "$ADDRESS" ]]; then
  echo "Usage: $0 <address> [amount_in_eth]"
  echo "  address        wallet address to fund"
  echo "  amount_in_eth  amount in ETH (default: 1)"
  exit 1
fi

# Convert ETH to wei (hex) — use bc for both to avoid 64-bit integer overflow
AMOUNT_WEI_HEX=0x$(echo "obase=16; $AMOUNT_ETH * 10^18 / 1" | bc)

echo "Funding $ADDRESS with $AMOUNT_ETH ETH ($AMOUNT_WEI_HEX wei)..."

curl -s -X POST "http://${CHAIN_HOST}:${CHAIN_RPC_PORT}" \
  -H 'Content-Type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"hardhat_setBalance\",\"params\":[\"$ADDRESS\",\"$AMOUNT_WEI_HEX\"],\"id\":1}" \
  | jq .

echo "Done."
