#!/bin/sh
. ./prelude.sh

github_clone graphprotocol/common-ts master

await_ready graph-contracts

cd build/graphprotocol/common-ts
cd packages/common-ts && yalc link @graphprotocol/contracts && yalc update && cd -
yalc link @graphprotocol/contracts && yalc update && yarn
cd packages/common-ts && yalc push && cd -

cd ../../..
signal_ready common-ts
