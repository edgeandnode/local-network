#!/bin/bash

# Mine n blocks, advancing time by 12 seconds per block to mimic Ethereum.
# Usage: mine-block.sh [count]

count=${1:-1}

RPC_URL="http://${CHAIN_HOST:-localhost}:${CHAIN_RPC_PORT:-8545}"

for ((i=0; i<count; i++))
do
    curl -sf "$RPC_URL" \
      -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"evm_increaseTime","params":[12],"id":1}' \
      > /dev/null

    cast rpc --rpc-url="$RPC_URL" evm_mine > /dev/null
done
