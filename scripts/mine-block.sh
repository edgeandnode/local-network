#!/bin/bash

# This script mines n blocks and advances the time by 12 seconds 
# each block to mimic the behavior of ethereum.


# Number of times to run the commands, default is 1
count=${1:-1}

RPC_URL="http://${CHAIN_HOST:-localhost}:${CHAIN_RPC_PORT:-8545}"

for ((i=0; i<count; i++))
do
    curl -X POST \
    -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"evm_increaseTime","params":[12],"id":1}' \
    "$RPC_URL"

    cast rpc --rpc-url="$RPC_URL" evm_mine
done
