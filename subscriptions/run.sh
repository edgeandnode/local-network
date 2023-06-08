#!/bin/sh
set -euf

if [ ! -d "build/edgeandnode/subscription-payments" ]; then
    mkdir -p build/edgeandnode/subscription-payments
    git clone git@github.com:edgeandnode/subscription-payments build/edgeandnode/subscription-payments --branch 'main'
fi

cd build/edgeandnode/subscription-payments/contract

yarn
yarn build
yarn deploy-local

contract_address="$(jq '.contract' contract-deployment.json)"

cd ../subgraph

yq ".dataSources[0].source.address |= ${contract_address}" -i subgraph.yaml
yq ".dataSources[0].network |= \"hardhat\"" -i subgraph.yaml
yarn
yarn create-local
yarn deploy-local
