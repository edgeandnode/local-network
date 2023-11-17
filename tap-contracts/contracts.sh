#!/bin/sh
set -euf

if [ ! -d "build/semiotic-ai/timeline-aggregation-protocol-contracts" ]; then
  mkdir -p build/semiotic-ai/timeline-aggregation-protocol-contracts
  git clone git@github.com:semiotic-ai/timeline-aggregation-protocol-contracts build/semiotic-ai/timeline-aggregation-protocol-contracts --branch main
fi

. ./.env

host="${DOCKER_GATEWAY_HOST:-host.docker.internal}"
echo "host=${host}"

echo "awaiting controller"
until curl -s "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done

echo "awaiting contracts"
curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/graph_contracts" >graph_contracts.json

staking=$(cat graph_contracts.json | jq -r '."1337".StakingExtension.address')
echo "staking=${staking}"
graph_token=$(cat graph_contracts.json | jq -r '."1337".GraphToken.address')
echo "graph_token=${graph_token}"

cd build/semiotic-ai/timeline-aggregation-protocol-contracts

export HARDHAT_DISABLE_TELEMETRY_PROMPT=true
yarn install
forge build

cast send --rpc-url "http://${host}:${CHAIN_RPC}" --private-key "${ACCOUNT0_SECRET_KEY}" --from "${ACCOUNT0_ADDRESS}" --value "0.01ether" "${GATEWAY_SIGNER_ADDRESS}"

allocation_tracker_deployment=$(forge create --rpc-url "http://${host}:${CHAIN_RPC}" --private-key "${GATEWAY_SIGNER_SECRET_KEY}" src/AllocationIDTracker.sol:AllocationIDTracker --json)
allocation_tracker=$(echo "${allocation_tracker_deployment}" | jq -r '.deployedTo')
echo "allocation_tracker=${allocation_tracker}"

tap_verifier_deployment=$(forge create --rpc-url "http://${host}:${CHAIN_RPC}" --private-key "${GATEWAY_SIGNER_SECRET_KEY}" src/TAPVerifier.sol:TAPVerifier --constructor-args 'tapVerifier' '1.0' --json)
tap_verifier=$(echo "${tap_verifier_deployment}" | jq -r '.deployedTo')
echo "tap_verifier=${tap_verifier}"

escrow_deployment=$(forge create --rpc-url "http://${host}:${CHAIN_RPC}" --private-key "${GATEWAY_SIGNER_SECRET_KEY}" src/Escrow.sol:Escrow --constructor-args "${graph_token}" "${staking}" "${tap_verifier}" "${allocation_tracker}" 10 15 --json)
escrow=$(echo "${escrow_deployment}" | jq -r '.deployedTo')
echo "escrow=${escrow}"

curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/scalar_tap_contracts" -d "{\"allocation_tracker\":\"${allocation_tracker}\",\"tap_verifier\":\"${tap_verifier}\",\"escrow\":\"${escrow}\"}"