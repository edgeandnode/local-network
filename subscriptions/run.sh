#!/bin/sh
set -euf

if [ ! -d "build/edgeandnode/subscription-payments" ]; then
    mkdir -p build/edgeandnode/subscription-payments
    git clone git@github.com:edgeandnode/subscription-payments build/edgeandnode/subscription-payments --branch 'main'
fi

. ./.env
host="${DOCKER_GATEWAY_HOST:-host.docker.internal}"

cd build/edgeandnode/subscription-payments/contract

yarn
sed -i "s+http://localhost:8545+http://${host}:${CHAIN_RPC}+g" hardhat.config.ts
yarn build
yarn deploy-local

contract_address="$(jq '.contract' contract-deployment.json)"

cd ../subgraph

yq ".dataSources[0].source.address |= ${contract_address}" -i subgraph.yaml
yq ".dataSources[0].network |= \"hardhat\"" -i subgraph.yaml
sed -i "s+http://localhost+http://${host}+g" package.json
yarn
yarn create-local
yarn deploy-local

cd ../cli
echo "${ACCOUNT0_SECRET_KEY}" | cargo run -- \
    --provider "http://${host}:${CHAIN_RPC}" \
    --subscriptions="$(jq -r '.contract' ../contract/contract-deployment.json)" \
    --token="$(jq -r '.token' ../contract/contract-deployment.json)" \
    subscribe --end="$(date -u '+%Y-%m-%dT%TZ' --date='10 hours')" --rate=100000000000000
