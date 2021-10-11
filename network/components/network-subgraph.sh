#!/usr/bin/env bash

set -e

########################################################################
# Run

cd $SUBGRAPH_SOURCES

yarn
yarn create:local
yarn deploy:hardhat
