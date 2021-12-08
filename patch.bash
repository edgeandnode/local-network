#!/usr/bin/env bash
source prelude.bash

find_replace_yalc() {
  find_replace_jq ".dependencies.\"${1}\"" "\"file:.yalc/${2}\"" "${3}"
}

pushd projects/edgeandnode/gateway
git switch ford/local-network
find_replace_yalc \
  @graphprotocol/common-ts \
  @graphprotocol/common-ts \
  package.json
find_replace_yalc \
  @graphprotocol/common-ts \
  @graphprotocol/common-ts \
  packages/gateway/package.json
find_replace_yalc \
  @edgeandnode/indexer-selection \
  @edgeandnode/indexer-selection \
  packages/query-engine/package.json
popd

pushd projects/edgeandnode/indexer-selection
find_replace_sed \
  "require('..\/native')" \
  "require('@edgeandnode\/indexer-selection\/native')" \
  lib/index.js
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

pushd projects/graphprotocol/common-ts/packages/common-ts/
git switch ford/local-network
find_replace_yalc @ethersproject/contracts @graphprotocol/contracts package.json
popd

pushd projects/graphprotocol/agora
find_replace_sed \
  '..\/native' \
  '@graphprotocol\/cost-model' \
  node-plugin/lib/index.js
popd

pushd projects/graphprotocol/graph-network-subgraph
git switch ford/local-network
find_replace_sed \
  '..\/..\/..\/contracts\/addresses.json' \
  '..\/..\/contracts\/addresses.json' \
  config/hardhatAddressScript.ts
# shellcheck disable=SC2016
find_replace_jq \
  '.scripts."deploy:hardhat"' \
  '"yarn && yarn prep:no-ipfs && yarn prepare:hardhat && graph deploy graphprotocol/graph-network --ipfs http://127.0.0.1:5001 --node http://localhost:8020 --version-label $(jq .label versionMetadata.json)"' \
  package.json
popd

pushd projects/graphprotocol/indexer
find_replace_yalc \
  @graphprotocol/contracts \
  @graphprotocol/contracts \
  packages/indexer-agent/package.json
find_replace_yalc \
  @graphprotocol/cost-model \
  @graphprotocol/cost-model \
  packages/indexer-common/package.json
find_replace_yalc \
  @graphprotocol/common-ts \
  @graphprotocol/common-ts \
  packages/indexer-{agent,cli,common,service}/package.json
# TODO: upstream
find_replace_jq \
  '.resolutions."@ethersproject/contracts"' \
  '"5.4.1"' \
  package.json
popd
