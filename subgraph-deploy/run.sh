#!/bin/sh
set -eu
. /opt/.env

# don't rerun when retriggered via a service_completed_successfully condition
if curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network" \
  -H 'content-type: application/json' \
  -d '{"query": "{ subgraphs { id } }" }' \
  | grep "${SUBGRAPH}"
then
  exit 0
fi

network_subgraph_deployment="$(curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network" \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { deployment } }" }' \
  | jq -r '.data._meta.deployment')"
block_oracle_deployment="$(curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/block-oracle" \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { deployment } }" }' \
  | jq -r '.data._meta.deployment')"
tap_deployment="$(curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/semiotic/tap" \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { deployment } }" }' \
  | jq -r '.data._meta.deployment')"

echo "network_subgraph_deployment=${network_subgraph_deployment}"
echo "block_oracle_deployment=${block_oracle_deployment}"
echo "tap_deployment=${tap_deployment}"

# force index block oracle subgraph & network subgraph
graph-indexer indexer connect "http://indexer-agent:${INDEXER_MANAGEMENT}"
graph-indexer indexer --network=hardhat rules prepare "${network_subgraph_deployment}" -o json
graph-indexer indexer --network=hardhat rules prepare "${block_oracle_deployment}" -o json
graph-indexer indexer --network=hardhat rules prepare "${tap_deployment}" -o json

deployment_hex="$(curl -s -X POST "http://ipfs:${IPFS_RPC}/api/v0/cid/format?arg=${block_oracle_deployment}&b=base16" \
  | jq -r '.Formatted')"
deployment_hex="${deployment_hex#f01701220}"
echo "deployment_hex=${deployment_hex}"
gns="$(jq -r '."1337".L2GNS.address' /opt/subgraph-service.json)"
cast send --rpc-url="http://chain:${CHAIN_RPC}" --confirmations=0 --mnemonic="${MNEMONIC}" \
  "${gns}" 'publishNewSubgraph(bytes32,bytes32,bytes32)' \
  "0x${deployment_hex}" \
  '0x0000000000000000000000000000000000000000000000000000000000000000' \
  '0x0000000000000000000000000000000000000000000000000000000000000000'

graph-indexer indexer --network=hardhat rules set "${block_oracle_deployment}" decisionBasis always -o json

while true; do
  # Fetch output from the command and handle errors
  if ! output=$(graph-indexer indexer --network=hardhat actions get -o json 2>&1); then
    echo "Error fetching output from graph-indexer, retrying..."
    sleep 2
  fi

  # Check for "success" in the output
  if echo "$output" | grep -q 'success'; then
    echo "Success detected, exiting loop."
    break
  fi

  echo "mining blocks in case the indexer-agent is stuck waiting for registration confirmations"
  echo "actions cli output: $output"

  # Mine a block and wait
  cast rpc --rpc-url="http://chain:${CHAIN_RPC}" evm_mine
  sleep 2
done


# wait for an active allocation
while ! curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network" \
  -H 'content-type: application/json' \
  -d '{"query": "{ allocations(where:{status:Active}) { indexer { id } } }" }' \
  | grep -i "${RECEIVER_ADDRESS}"
do
  sleep 2
done
