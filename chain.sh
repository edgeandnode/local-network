#!/bin/sh
. ./prelude.sh

github_clone graphprotocol/contracts v2.1.0
cd build/graphprotocol/contracts

# TODO: How should we determine the authority address?
find_replace_sed \
  '\&authority "0xE11BA2b4D45Eaed5996Cd0823791E0C93114882d"' \
  '\&authority "0x5d0365e8dcbd1b00fc780b206e85c9d78159a865"' \
  config/graph.localhost.yml
find_replace_sed \
  '- fn: "renounceMinter"' \
  '# - fn: "renounceMinter"' \
  config/graph.localhost.yml

cp ../../../subgraphMetadata.json ../../../versionMetadata.json ./cli

yarn install --non-interactive --frozen-lockfile
yarn build

npx hardhat node
