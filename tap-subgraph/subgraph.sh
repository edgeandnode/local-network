#!/bin/sh
set -euf

if [ ! -d "build/semiotic-ai/timeline-aggregation-protocol-subgraph" ]; then
  mkdir -p build/semiotic-ai/timeline-aggregation-protocol-subgraph
  git clone git@github.com:semiotic-ai/timeline-aggregation-protocol-subgraph build/semiotic-ai/timeline-aggregation-protocol-subgraph --branch 'main' --recursive
fi

. ./.env

echo "awaiting controller"
until curl -s "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done

echo "awaiting IPFS"
until curl -s "http://${DOCKER_GATEWAY_HOST}:${IPFS_RPC}/api/v0/version" -X POST > /dev/null; do sleep 1; done

echo "awaiting graph-node"
until curl -s "http://${DOCKER_GATEWAY_HOST}:${GRAPH_NODE_STATUS}" >/dev/null; do sleep 1; done

echo "awaiting scalar-tap-contracts"
curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/scalar_tap_contracts" >scalar_tap_contracts.json

host="${DOCKER_GATEWAY_HOST:-host.docker.internal}"
echo "host=${host}"

escrow=$(cat scalar_tap_contracts.json | jq -r '.escrow')
echo "escrow=${escrow}"

cd build/semiotic-ai/timeline-aggregation-protocol-subgraph

# yarn add --dev @graphprotocol/graph-cli
sed -i "s+http://127.0.0.1:5001+http://${host}:${IPFS_RPC}+g" package.json
sed -i "s+http://127.0.0.1:8020+http://${host}:${GRAPH_NODE_ADMIN}+g" package.json
yq ".dataSources[].source.address=\"${escrow}\"" -i subgraph.yaml
yq ".dataSources[].network |= \"hardhat\"" -i subgraph.yaml
yarn codegen
yarn build
yarn create-local
yarn deploy-local --version-label v0.0.1 | tee subgraph-deploy.txt
subgraph_deployment="$(grep "Build completed: " subgraph-deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"
echo "subgraph_deployment=${subgraph_deployment}"

# echo "awaiting controller"
# until curl -s "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done
# 
# echo "awaiting contracts"
# curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/graph_contracts" >graph_contracts.json
# 
# staking=$(cat graph_contracts.json | jq -r '."1337".StakingExtension.address')
# echo "staking=${staking}"
# graph_token=$(cat graph_contracts.json | jq -r '."1337".GraphToken.address')
# echo "graph_token=${graph_token}"
# 
# cd build/semiotic-ai/timeline-aggregation-protocol-contracts
# 
# export HARDHAT_DISABLE_TELEMETRY_PROMPT=true
# yarn install
# forge build
# 
# cast send --rpc-url "http://${host}:${CHAIN_RPC}" --private-key "${ACCOUNT0_SECRET_KEY}" --from "${ACCOUNT0_ADDRESS}" --value "0.01ether" "${GATEWAY_SIGNER_ADDRESS}"
# 
# allocation_tracker_deployment=$(forge create --rpc-url "http://${host}:${CHAIN_RPC}" --private-key "${GATEWAY_SIGNER_SECRET_KEY}" src/AllocationIDTracker.sol:AllocationIDTracker --json)
# allocation_tracker=$(echo "${allocation_tracker_deployment}" | jq -r '.deployedTo')
# echo "allocation_tracker=${allocation_tracker}"
# 
# tap_verifier_deployment=$(forge create --rpc-url "http://${host}:${CHAIN_RPC}" --private-key "${GATEWAY_SIGNER_SECRET_KEY}" src/TAPVerifier.sol:TAPVerifier --constructor-args 'tapVerifier' '1.0' --json)
# tap_verifier=$(echo "${tap_verifier_deployment}" | jq -r '.deployedTo')
# echo "tap_verifier=${tap_verifier}"
# 
# escrow_deployment=$(forge create --rpc-url "http://${host}:${CHAIN_RPC}" --private-key "${GATEWAY_SIGNER_SECRET_KEY}" src/Escrow.sol:Escrow --constructor-args "${graph_token}" "${staking}" "${tap_verifier}" "${allocation_tracker}" 10 15 --json)
# escrow=$(echo "${escrow_deployment}" | jq -r '.deployedTo')
# echo "escrow=${escrow}"
# 
# curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/scalar_tap_contracts" -d "{\"allocation_tracker\":\"${allocation_tracker}\",\"tap_verifier\":\"${tap_verifier}\",\"escrow\":\"${escrow}\"}"