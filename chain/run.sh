#!/bin/sh
set -euf

if [ ! -d "build/graphprotocol/contracts" ]; then
  mkdir -p build/graphprotocol/contracts
  git clone git@github.com:graphprotocol/contracts build/graphprotocol/contracts --branch 'theodus/v5.1.0'
fi

cd build/graphprotocol/contracts

# TODO: How should we determine the authority address?
yq -i '.general.authority |= "0x5d0365e8dcbd1b00fc780b206e85c9d78159a865"' \
  config/graph.localhost.yml

yarn

(
  ready_code=1
  while [ ${ready_code} -ne 0 ]; do
    sleep 1
    curl -sf curl "localhost:8545"
    ready_code=$?
  done

  curl "localhost:8545" -X POST --data \
    '{"jsonrpc":"2.0","method":"hardhat_setLoggingEnabled","params":[true],"id":1}'
  curl "localhost:8545" -X POST --data \
    '{"jsonrpc":"2.0","method":"evm_mine","params":[],"id":1}'
) &

npx hardhat node --hostname 0.0.0.0
