set -xe
source .env
[ -f .env.local ] && source .env.local
name=$1
if [ -z "$name" ]; then
  echo "Usage: $0 <name>"
  exit 1
fi
GRAPH_NODE_HOST="${GRAPH_NODE_HOST:-localhost}"
IPFS_HOST="${IPFS_HOST:-localhost}"
CHAIN_HOST="${CHAIN_HOST:-localhost}"
INDEXER_AGENT_HOST="${INDEXER_AGENT_HOST:-localhost}"

deployment="$(curl -s "http://${GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/$name" \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { deployment } }" }' \
  | jq -r '.data._meta.deployment')"
echo "deployment=${deployment}"
deployment_hex="$(curl -s -X POST "http://${IPFS_HOST}:${IPFS_RPC_PORT}/api/v0/cid/format?arg=${deployment}&b=base16" \
  | jq -r '.Formatted')"

# Remove the first 8 bytes of the hex string matching the IPFS prefix
deployment_hex="${deployment_hex#f01701220}"

echo "deployment_hex=${deployment_hex}"
gns="$(docker exec graph-node cat /opt/config/subgraph-service.json | jq -r '."1337".L2GNS.address')"

# https://github.com/graphprotocol/contracts/blob/3eb16c80d4652c238d3e6b2c396da712af5072b4/packages/sdk/src/deployments/network/actions/gns.ts#L38
cast send --rpc-url="http://${CHAIN_HOST}:${CHAIN_RPC_PORT}" --confirmations=0 --mnemonic="${MNEMONIC}" \
  "${gns}" 'publishNewSubgraph(bytes32,bytes32,bytes32)' \
  "0x${deployment_hex}" \
  '0x0000000000000000000000000000000000000000000000000000000000000000' \
  '0x0000000000000000000000000000000000000000000000000000000000000000'

set +x

echo
echo "Now run graph indexer to allocate to this subgraph ${deployment} :"
echo "------------------------------------------------------------------"
echo
echo "./bin/graph-indexer indexer connect \"http://${INDEXER_AGENT_HOST}:${INDEXER_MANAGEMENT_PORT}\""
echo "./bin/graph-indexer indexer actions queue allocate ${deployment} 0.001 --network=hardhat"
echo "./bin/graph-indexer indexer actions get"
echo "./bin/graph-indexer indexer actions update --id [id] status approved"
