#!/usr/bin/env bash
source prelude.bash

cd projects/graphprotocol/contracts
npx hardhat node 2>&1| tee /tmp/chain.log
