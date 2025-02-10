#!/bin/bash

# Number of times to run the commands, default is 1
count=${1:-1}

for ((i=0; i<count; i++))
do
    curl -X POST \
    -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"evm_increaseTime","params":[3600],"id":1}' \
    http://localhost:8545

    cast rpc --rpc-url="http://localhost:8545" evm_mine
done
