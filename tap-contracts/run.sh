#!/bin/sh
set -eu
. /opt/.env

# don't rerun when retriggered via a service_completed_successfully condition
if curl -s http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/semiotic/tap \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { deployment } }" }' | \
  grep "_meta"
then
  exit 0
fi

export PATH="/root/.foundry/bin:${PATH}"

cd /opt/timeline-aggregation-protocol-contracts

staking=$(jq -r '."1337".L1Staking.address' /opt/contracts.json)
graph_token=$(jq -r '."1337".GraphToken.address' /opt/contracts.json)

forge create --broadcast --json --rpc-url="http://chain:${CHAIN_RPC}" --mnemonic="${MNEMONIC}" \
  src/AllocationIDTracker.sol:AllocationIDTracker \
  | tee allocation_tracker.json
allocation_tracker="$(jq -r '.deployedTo' allocation_tracker.json)"
test "${allocation_tracker}" = "$(jq -r '."1337".TAPAllocationIDTracker.address' /opt/contracts.json)"

forge create --broadcast --json --rpc-url="http://chain:${CHAIN_RPC}" --mnemonic="${MNEMONIC}" \
  src/TAPVerifier.sol:TAPVerifier --constructor-args 'TAP' '1' \
  | tee verifier.json
verifier="$(jq -r '.deployedTo' verifier.json)"
test "${verifier}" = "$(jq -r '."1337".TAPVerifier.address' /opt/contracts.json)"

forge create --broadcast --json --rpc-url="http://chain:${CHAIN_RPC}" --mnemonic="${MNEMONIC}" \
  src/Escrow.sol:Escrow --constructor-args "${graph_token}" "${staking}" "${verifier}" "${allocation_tracker}" 10 15 \
  | tee escrow.json
escrow="$(jq -r '.deployedTo' escrow.json)"
test "${escrow}" = "$(jq -r '."1337".TAPEscrow.address' /opt/contracts.json)"

cd /opt/timeline-aggregation-protocol-subgraph
sed -i "s/127.0.0.1:5001/ipfs:${IPFS_RPC}/g" package.json
sed -i "s/127.0.0.1:8020/graph-node:${GRAPH_NODE_ADMIN}/g" package.json
yq ".dataSources[].source.address=\"${escrow}\"" -i subgraph.yaml
yq ".dataSources[].network |= \"hardhat\"" -i subgraph.yaml
yarn codegen
yarn build
yarn create-local
yarn deploy-local | tee deploy.txt
deployment_id="$(grep "Build completed: " deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"
echo "${deployment_id}"
curl -s "http://graph-node:${GRAPH_NODE_ADMIN}" \
  -H 'content-type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"subgraph_reassign\",\"params\":{\"node_id\":\"default\",\"ipfs_hash\":\"${deployment_id}\"}}" && \
  echo ""
