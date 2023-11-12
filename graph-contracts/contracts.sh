#!/bin/sh
set -euf

if [ ! -d "build/graphprotocol/contracts" ]; then
  mkdir -p build/graphprotocol/contracts
  git clone git@github.com:graphprotocol/contracts build/graphprotocol/contracts --branch 'v5.3.0'
fi

. ./.env

until curl -s "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done

cd build/graphprotocol/contracts

export HARDHAT_DISABLE_TELEMETRY_PROMPT=true
yarn

sed -i "s+http://localhost:8545+http://${DOCKER_GATEWAY_HOST}:${CHAIN_RPC}+g" hardhat.config.ts
yq -i ".general.authority |= \"${GATEWAY_SIGNER_ADDRESS}\"" config/graph.localhost.yml

yarn deploy-localhost --skip-confirmation

# reset chain options, since deploy messes with them
curl "http://${DOCKER_GATEWAY_HOST}:${CHAIN_RPC}" \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"evm_setAutomine","params":[true]}'
curl "http://${DOCKER_GATEWAY_HOST}:${CHAIN_RPC}" \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"anvil_setLoggingEnabled","params":[true]}'

cast send "--rpc-url=http://${DOCKER_GATEWAY_HOST}:${CHAIN_RPC}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
  "$(cat addresses.json | jq -r '."1337".EpochManager.address')" \
  'setEpochLength(uint256)' 4

cast send "--rpc-url=http://${DOCKER_GATEWAY_HOST}:${CHAIN_RPC}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
  "$(cat addresses.json | jq -r '."1337".RewardsManager.address')" \
  'setSubgraphAvailabilityOracle(address)' "${SAO_ADDRESS}"

cast send "--rpc-url=http://${DOCKER_GATEWAY_HOST}:${CHAIN_RPC}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
  "$(cat addresses.json | jq -r '."1337".Controller.address')" \
  'setPaused(bool)' false

graph_contracts="$(jq <addresses.json -r 'with_entries(select(.key | in({"1337":1}))) | tostring')"
curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/graph_contracts" -d "${graph_contracts}"
