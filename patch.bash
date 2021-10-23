#!/usr/bin/env bash
source prelude.bash

pushd projects/graphprotocol/contracts
git switch ford/local-network
cp ../../../{subgraph,version}Metadata.json ./cli
find_replace '_src\/\*.ts' '_src\/types\/\*.ts' scripts/prepublish
popd
pushd projects/graphprotocol/common-ts/packages/common-ts/
updated=$(jq '.dependencies."@ethersproject/contracts" |= "file:.yalc/@graphprotocol/contracts"' package.json)
echo "${updated}" >package.json
popd
