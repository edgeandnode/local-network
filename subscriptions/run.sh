#!/bin/sh
set -euf

if [ ! -d "build/edgeandnode/subscription-payments" ]; then
    mkdir -p build/edgeandnode/subscription-payments
    git clone git@github.com:edgeandnode/subscription-payments build/edgeandnode/subscription-payments --branch 'main'
fi

. ./.env

cd build/edgeandnode/subscription-payments/contracts

# yarn
# yarn build
# yarn deploy-local

contract_address="$(jq -r '.contract' contract-deployment.json)"
token_address="$(jq -r '.token' contract-deployment.json)"

cd ../subgraph

yarn
yarn prepare
yq ".dataSources[0].source.address |= \"${contract_address}\"" -i subgraph.yaml
yq ".dataSources[0].network |= \"hardhat\"" -i subgraph.yaml
yarn
yarn create-local
yarn deploy-local

cd ../cli

echo "${ACCOUNT0_SECRET_KEY}" | cargo run -- \
  --provider="http://${DOCKER_GATEWAY_HOST}:${CHAIN_RPC}" \
  --chain-id=1337 \
  --subscriptions="${contract_address}" \
  --token="${token_address}" \
  ticket
