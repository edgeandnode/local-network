#!/bin/sh
. ./prelude.sh

github_clone graphprotocol/contracts v1.11.0
cd build/graphprotocol/contracts

# TODO: How should we determine the authority address?
find_replace_sed \
  '\&authority "0x79fd74da4c906509862c8fe93e87a9602e370bc4"' \
  '\&authority "0x5d0365e8dcbd1b00fc780b206e85c9d78159a865"' \
  graph.config.yml
cp ../../../subgraphMetadata.json ../../../versionMetadata.json ./cli

yarn --non-interactive
yarn build

npx hardhat node
