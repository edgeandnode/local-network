#!/usr/bin/env bash
source prelude.bash

pushd projects/edgeandnode/gateway
git switch theodus/local-network
popd

pushd projects/edgeandnode/indexer-selection
git switch theodus/neon-update
find_replace_sed \
  "require('..\/native')" \
  "require('@edgeandnode\/indexer-selection\/native')" \
  lib/index.js
popd

pushd projects/edgeandnode/network-services
git switch ford/local-network
popd

pushd projects/edgeandnode/subgraph-studio
git switch ford/local-network
popd

pushd projects/graphprotocol/contracts
git checkout 0877142
cp ../../../{subgraph,version}Metadata.json ./cli
# TODO: upstream
find_replace_sed '_src\/\*.ts' '_src\/types\/\*.ts' scripts/prepublish
popd

pushd projects/graphprotocol/agora
find_replace_sed \
  '..\/native' \
  '@graphprotocol\/cost-model' \
  node-plugin/lib/index.js
popd

pushd projects/graphprotocol/graph-network-subgraph
git switch theodus/local-network
find_replace_sed \
  '..\/..\/..\/contracts\/addresses.json' \
  '..\/..\/contracts\/addresses.json' \
  config/hardhatAddressScript.ts
# shellcheck disable=SC2016
find_replace_jq \
  '.scripts."deploy:hardhat"' \
  '"yarn && yarn prep:no-ipfs && yarn prepare:hardhat && graph deploy graphprotocol/graph-network --ipfs http://127.0.0.1:5001 --node http://127.0.0.1:8020 --version-label $(jq .label versionMetadata.json)"' \
  package.json
find_replace_sed 'localhost' '127.0.0.1' package.json
popd
