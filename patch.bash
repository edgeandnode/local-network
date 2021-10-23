#!/usr/bin/env bash
source prelude.bash

find_replace_yalc() {
  find_replace_jq ".dependencies.\"${1}\"" "\"file:.yalc/${2}\"" "${3}"
}

pushd projects/graphprotocol/contracts
# TODO: rm?
# git switch ford/local-network
cp ../../../{subgraph,version}Metadata.json ./cli
# TODO: upstream
find_replace_sed '_src\/\*.ts' '_src\/types\/\*.ts' scripts/prepublish
popd

pushd projects/graphprotocol/common-ts/packages/common-ts/
find_replace_yalc @ethersproject/contracts @graphprotocol/contracts package.json
popd

pushd projects/graphprotocol/cost-model
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
popd

# pushd graphprotocol/graph-node
# popd

pushd projects/graphprotocol/indexer
git switch ford/local-network
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
