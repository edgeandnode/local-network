#!/bin/sh
. ./prelude.sh

github_clone graphprotocol/contracts v1.11.0
cd build/graphprotocol/contracts

yarn --non-interactive
npx hardhat node
