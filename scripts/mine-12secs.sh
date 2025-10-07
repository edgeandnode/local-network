#!/bin/bash

# This script mines 1 block every 12 seconds to simulate the behavior of ethereum.

export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

block_time=12

echo "Mining blocks every $block_time seconds..."
while true; do
    echo "⛏️  Mining block..."
    curl -s -X POST \
      -H "Content-Type: application/json" \
      --data '{"jsonrpc":"2.0","method":"evm_increaseTime","params":['$block_time'],"id":1}' \
      http://localhost:8545 > /dev/null

    cast rpc --rpc-url="http://localhost:8545" evm_mine > /dev/null

    block_number=$(cast block-number --rpc-url http://localhost:8545)
    echo "📦 Latest block: $block_number"

    sleep $block_time
done