#!/bin/bash
set -xeu
. /opt/.env

token_address=$(jq -r '."1337".GraphToken.address' /opt/contracts.json)
staking_address=$(jq -r '."1337".L1Staking.address' /opt/contracts.json)
indexer_staked="$(cast call "--rpc-url=http://chain:${CHAIN_RPC}" \
  "${staking_address}" 'hasStake(address) (bool)' "${RECEIVER_ADDRESS}")"
echo "indexer_staked=${indexer_staked}"
if [ "${indexer_staked}" = "false" ]; then
  # transfer ETH to receiver
  cast send "--rpc-url=http://chain:${CHAIN_RPC}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
    --value=1ether "${RECEIVER_ADDRESS}"
  # transfer 100,000 GRT to receiver
  cast send "--rpc-url=http://chain:${CHAIN_RPC}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
    "${token_address}" 'transfer(address,uint256)' "${RECEIVER_ADDRESS}" '100000000000000000000000'
  # stake required GRT for indexer registration
  cast send "--rpc-url=http://chain:${CHAIN_RPC}" --confirmations=0 "--private-key=${RECEIVER_SECRET}" \
    "${token_address}" 'approve(address,uint256)' "${staking_address}" '100000000000000000000000'
  cast send "--rpc-url=http://chain:${CHAIN_RPC}" --confirmations=0 "--private-key=${RECEIVER_SECRET}" \
    "${staking_address}" 'stake(uint256)' '100000000000000000000000'
fi

export INDEXER_AGENT_ADDRESS_BOOK=/opt/contracts.json
export INDEXER_AGENT_TAP_ADDRESS_BOOK=./tap-contracts.json
export INDEXER_AGENT_EPOCH_SUBGRAPH_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/block-oracle"
export INDEXER_AGENT_GATEWAY_ENDPOINT="http://gateway:${GATEWAY}"
export INDEXER_AGENT_GRAPH_NODE_QUERY_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL}"
export INDEXER_AGENT_GRAPH_NODE_ADMIN_ENDPOINT="http://graph-node:${GRAPH_NODE_ADMIN}"
export INDEXER_AGENT_GRAPH_NODE_STATUS_ENDPOINT="http://graph-node:${GRAPH_NODE_STATUS}/graphql"
export INDEXER_AGENT_IPFS_ENDPOINT="http://ipfs:${IPFS_RPC}"
export INDEXER_AGENT_INDEXER_ADDRESS="${RECEIVER_ADDRESS}"
export INDEXER_AGENT_INDEXER_MANAGEMENT_PORT="${INDEXER_MANAGEMENT}"
export INDEXER_AGENT_INDEX_NODE_IDS=default
export INDEXER_AGENT_INDEXER_GEO_COORDINATES="1 1"
export INDEXER_AGENT_NETWORK_SUBGRAPH_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network"
export INDEXER_AGENT_NETWORK_PROVIDER="http://chain:${CHAIN_RPC}"
export INDEXER_AGENT_MNEMONIC="${INDEXER_MNEMONIC}"
export INDEXER_AGENT_POSTGRES_DATABASE=indexer_components_1
export INDEXER_AGENT_POSTGRES_HOST=postgres
export INDEXER_AGENT_POSTGRES_PORT="${POSTGRES}"
export INDEXER_AGENT_POSTGRES_USERNAME=postgres
export INDEXER_AGENT_POSTGRES_PASSWORD=
export INDEXER_AGENT_PUBLIC_INDEXER_URL="http://indexer-service-ts:${INDEXER_SERVICE}"
export INDEXER_AGENT_TAP_SUBGRAPH_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/semiotic/tap"

cd /opt/indexer-agent-source-root
mkdir -p ./config/
cat >./config/config.yaml <<-EOF
networkIdentifier: "hardhat"
indexerOptions:
  geoCoordinates: [48.4682, -123.524]
  defaultAllocationAmount: 10000
  allocationManagementMode: "auto"
  restakeRewards: true
  poiDisputeMonitoring: false
  voucherRedemptionThreshold: 0.00001
  voucherRedemptionBatchThreshold: 10
  rebateClaimThreshold: 0.00001
  rebateClaimBatchThreshold: 10
subgraphs:
  maxBlockDistance: 5000
  freshnessSleepMilliseconds: 1000
EOF
cat config/config.yaml
cat >./tap-contracts.json <<-EOF
{
  "1337": {
    "TAPVerifier": "$(jq -r '."1337".TAPVerifier.address' /opt/contracts.json)",
    "AllocationIDTracker": "$(jq -r '."1337".TAPAllocationIDTracker.address' /opt/contracts.json)",
    "Escrow": "$(jq -r '."1337".TAPEscrow.address' /opt/contracts.json)"
  }
}
EOF
cat tap-contracts.json

cat ./config/config.yaml
echo "Current PWD $PWD"

nodemon --watch . \
--ext js \
--legacy-watch \
--delay 4 \
--verbose \
--exec "
NODE_OPTIONS=\"--inspect=0.0.0.0:9230\"
ts-node \
  packages/indexer-agent/src/index.ts start

# TODO: port this script to use a config file...
# --network-specifications-directory /opt/network-configs/"
