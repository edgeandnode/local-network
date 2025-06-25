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

staking=$(jq -r '."1337".HorizonStaking.address' /opt/horizon.json)
graph_token=$(jq -r '."1337".L2GraphToken.address' /opt/horizon.json)

forge create --broadcast --json --rpc-url="http://chain:${CHAIN_RPC}" --mnemonic="${MNEMONIC}" \
  src/AllocationIDTracker.sol:AllocationIDTracker \
  | tee allocation_tracker.json
allocation_tracker="$(jq -r '.deployedTo' allocation_tracker.json)"

forge create --broadcast --json --rpc-url="http://chain:${CHAIN_RPC}" --mnemonic="${MNEMONIC}" \
  src/TAPVerifier.sol:TAPVerifier --constructor-args 'TAP' '1' \
  | tee verifier.json
verifier="$(jq -r '.deployedTo' verifier.json)"

forge create --broadcast --json --rpc-url="http://chain:${CHAIN_RPC}" --mnemonic="${MNEMONIC}" \
  src/Escrow.sol:Escrow --constructor-args "${graph_token}" "${staking}" "${verifier}" "${allocation_tracker}" 10 15 \
  | tee escrow.json
escrow="$(jq -r '.deployedTo' escrow.json)"

cat <<EOF > /opt/tap-contracts.json
{
  "1337": {
    "TAPAllocationIDTracker": {
      "address": "$allocation_tracker"
    },
    "TAPVerifier": {
      "address": "$verifier"
    },
    "TAPEscrow": {
      "address": "$escrow"
    }
  }
}
EOF


# Deploy TAP v1 subgraph (original - services expect semiotic/tap)
echo "Deploying TAP v1 subgraph..."
cd /opt/timeline-aggregation-protocol-subgraph
sed -i "s/127.0.0.1:5001/ipfs:${IPFS_RPC}/g" package.json
sed -i "s/127.0.0.1:8020/graph-node:${GRAPH_NODE_ADMIN}/g" package.json
yq ".dataSources[].source.address=\"${escrow}\"" -i subgraph.yaml
yq ".dataSources[].network |= \"hardhat\"" -i subgraph.yaml
# Bypass Node.js version check by ignoring engines for Node 24 compatibility
yarn install --ignore-engines
yarn codegen
yarn build
# Create and deploy as semiotic/tap (which services expect)
yarn run graph create --node http://graph-node:${GRAPH_NODE_ADMIN}/ semiotic/tap
yarn run graph deploy --node http://graph-node:${GRAPH_NODE_ADMIN}/ --ipfs http://ipfs:${IPFS_RPC} --version-label v1.0.0 semiotic/tap | tee deploy.txt
deployment_id_v1="$(grep "Build completed: " deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"
echo "TAP v1 deployment: ${deployment_id_v1}"
curl -s "http://graph-node:${GRAPH_NODE_ADMIN}" \
  -H 'content-type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"subgraph_reassign\",\"params\":{\"node_id\":\"default\",\"ipfs_hash\":\"${deployment_id_v1}\"}}" && \
  echo ""

# Deploy TAP v2 subgraph (different contracts)
echo "Deploying TAP v2 subgraph..."
cd /opt/tapV2-subgraph
sed -i "s/127.0.0.1:5001/ipfs:${IPFS_RPC}/g" package.json
sed -i "s/127.0.0.1:8020/graph-node:${GRAPH_NODE_ADMIN}/g" package.json
sed -i "s/localhost:5001/ipfs:${IPFS_RPC}/g" package.json
sed -i "s/localhost:8020/graph-node:${GRAPH_NODE_ADMIN}/g" package.json

# Generate subgraph.yaml from template
cp subgraph.template.yaml subgraph.yaml
# Replace template placeholders
sed -i "s/{{network}}/hardhat/g" subgraph.yaml
sed -i "s/{{TapCollector.address}}/${escrow}/g" subgraph.yaml
sed -i "s/{{TapCollector.startBlock}}/1/g" subgraph.yaml
sed -i "s/{{PaymentsEscrow.address}}/${escrow}/g" subgraph.yaml
sed -i "s/{{PaymentsEscrow.startBlock}}/1/g" subgraph.yaml

# Fix schema entity definitions to add immutable argument
sed -i 's/@entity{/@entity(immutable: false) {/g' schema.graphql
sed -i 's/@entity {/@entity(immutable: false) {/g' schema.graphql
yarn codegen
yarn build
# Deploy v2 as separate subgraph since it indexes different contracts
yarn run graph create --node http://graph-node:${GRAPH_NODE_ADMIN}/ semiotic/tap-v2
yarn run graph deploy --node http://graph-node:${GRAPH_NODE_ADMIN}/ --ipfs http://ipfs:${IPFS_RPC} --version-label v2.0.0 semiotic/tap-v2 | tee deploy.txt
deployment_id_v2="$(grep "Build completed: " deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"
echo "TAP v2 deployment: ${deployment_id_v2}"
curl -s "http://graph-node:${GRAPH_NODE_ADMIN}" \
  -H 'content-type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"subgraph_reassign\",\"params\":{\"node_id\":\"default\",\"ipfs_hash\":\"${deployment_id_v2}\"}}" && \
  echo ""