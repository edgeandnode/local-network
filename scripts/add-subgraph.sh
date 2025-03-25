#!/bin/env bash
set -xe
source "$PWD/.env"

name=$1
if [ -z "$name" ]; then
  echo "Add a subgraph to the graph-network"
  echo "Usage: $0 <name>"
  echo "  <name> The name of the subgraph in the graph-node"
  exit 1
fi

# Get the deployment hash from the graph-node
deployment="$(curl -s "http://localhost:${GRAPH_NODE_GRAPHQL}/subgraphs/name/$name" \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { deployment } }" }' \
  | jq -r '.data._meta.deployment')"
echo "deployment=${deployment}"

# Extract the deployment hash from the IPFS CID and strip the IPFS CID prefix
deployment_hex="$(curl -s -X POST "http://localhost:${IPFS_RPC}/api/v0/cid/format?arg=${deployment}&b=base16" \
  | jq -r '.Formatted' | sed 's/^f01701220//')"
echo "deployment_hex=${deployment_hex}"

# Get the GNS address for the chain
gns="$(jq -r ".\"${CHAIN_ID}\".L1GNS.address" contracts.json)"
# https://github.com/graphprotocol/contracts/blob/3eb16c80d4652c238d3e6b2c396da712af5072b4/packages/sdk/src/deployments/network/actions/gns.ts#L38
cast send --rpc-url="http://localhost:${CHAIN_RPC}" --confirmations=0 --mnemonic="${MNEMONIC}" \
  "${gns}" 'publishNewSubgraph(bytes32,bytes32,bytes32)' \
  "0x${deployment_hex}" \
  '0x0000000000000000000000000000000000000000000000000000000000000000' \
  '0x0000000000000000000000000000000000000000000000000000000000000000'

set +x

echo
echo "Now run graph indexer to allocate to this subgraph ${deployment} :"
echo "------------------------------------------------------------------"
echo
echo "./bin/graph-indexer indexer connect \"http://localhost:${INDEXER_MANAGEMENT}\""
echo "./bin/graph-indexer indexer actions queue allocate ${deployment} 0.001 --network=${CHAIN_NAME}"
echo "./bin/graph-indexer indexer actions get"
echo "./bin/graph-indexer indexer actions update --id [id] status approved"
