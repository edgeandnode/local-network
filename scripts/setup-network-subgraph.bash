#!/usr/bin/env bash
source prelude.bash

cd projects/graphprotocol/graph-network-subgraph
yarn create:local
yarn deploy:hardhat
