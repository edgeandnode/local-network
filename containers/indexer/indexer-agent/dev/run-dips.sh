#!/bin/bash
set -xeu
. /opt/config/.env

. /opt/shared/lib.sh

token_address=$(contract_addr L2GraphToken.address horizon)
staking_address=$(contract_addr HorizonStaking.address horizon)
indexer_staked="$(cast call "--rpc-url=http://chain:${CHAIN_RPC_PORT}" \
  "${staking_address}" 'hasStake(address) (bool)' "${RECEIVER_ADDRESS}")"
echo "indexer_staked=${indexer_staked}"
if [ "${indexer_staked}" = "false" ]; then
  cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
    --value=1ether "${RECEIVER_ADDRESS}"
  cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
    "${token_address}" 'transfer(address,uint256)' "${RECEIVER_ADDRESS}" '100000000000000000000000'
  cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--private-key=${RECEIVER_SECRET}" \
    "${token_address}" 'approve(address,uint256)' "${staking_address}" '100000000000000000000000'
  cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--private-key=${RECEIVER_SECRET}" \
    "${staking_address}" 'stake(uint256)' '100000000000000000000000'
fi

export INDEXER_AGENT_HORIZON_ADDRESS_BOOK=/opt/config/horizon.json
export INDEXER_AGENT_SUBGRAPH_SERVICE_ADDRESS_BOOK=/opt/config/subgraph-service.json
export INDEXER_AGENT_TAP_ADDRESS_BOOK=/opt/config/tap-contracts.json
export INDEXER_AGENT_EPOCH_SUBGRAPH_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/block-oracle"
export INDEXER_AGENT_GATEWAY_ENDPOINT="http://gateway:${GATEWAY_PORT}"
export INDEXER_AGENT_GRAPH_NODE_QUERY_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}"
export INDEXER_AGENT_GRAPH_NODE_ADMIN_ENDPOINT="http://graph-node:${GRAPH_NODE_ADMIN_PORT}"
export INDEXER_AGENT_GRAPH_NODE_STATUS_ENDPOINT="http://graph-node:${GRAPH_NODE_STATUS_PORT}/graphql"
export INDEXER_AGENT_IPFS_ENDPOINT="http://ipfs:${IPFS_RPC_PORT}"
export INDEXER_AGENT_INDEXER_ADDRESS="${RECEIVER_ADDRESS}"
export INDEXER_AGENT_INDEXER_MANAGEMENT_PORT="${INDEXER_MANAGEMENT_PORT}"
export INDEXER_AGENT_INDEX_NODE_IDS=default
export INDEXER_AGENT_INDEXER_GEO_COORDINATES="1 1"
export INDEXER_AGENT_VOUCHER_REDEMPTION_THRESHOLD=0.01
export INDEXER_AGENT_NETWORK_SUBGRAPH_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network"
export INDEXER_AGENT_NETWORK_PROVIDER="http://chain:${CHAIN_RPC_PORT}"
export INDEXER_AGENT_MNEMONIC="${INDEXER_MNEMONIC}"
export INDEXER_AGENT_POSTGRES_DATABASE=indexer_components_1
export INDEXER_AGENT_POSTGRES_HOST=postgres
export INDEXER_AGENT_POSTGRES_PORT="${POSTGRES_PORT}"
export INDEXER_AGENT_POSTGRES_USERNAME=postgres
export INDEXER_AGENT_POSTGRES_PASSWORD=
export INDEXER_AGENT_PUBLIC_INDEXER_URL="http://indexer-service:${INDEXER_SERVICE_PORT}"
export INDEXER_AGENT_TAP_SUBGRAPH_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/semiotic/tap"
export INDEXER_AGENT_MAX_PROVISION_INITIAL_SIZE=200000
export INDEXER_AGENT_CONFIRMATION_BLOCKS=1
export INDEXER_AGENT_LOG_LEVEL=trace

# DIPs configuration
export INDEXER_AGENT_ENABLE_DIPS=true
export INDEXER_AGENT_DIPS_EPOCHS_MARGIN=1
export INDEXER_AGENT_DIPPER_ENDPOINT="http://dipper:${DIPPER_INDEXER_RPC_PORT}"
export INDEXER_AGENT_DIPS_ALLOCATION_AMOUNT=1

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
enableDips: true
dipperEndpoint: "http://dipper:${DIPPER_INDEXER_RPC_PORT}"
dipsAllocationAmount: 1
dipsEpochsMargin: 1
EOF
cat config/config.yaml

nodemon --watch . \
--ext ts \
--legacy-watch \
--delay 4 \
--verbose \
--exec "
NODE_OPTIONS=\"--inspect=0.0.0.0:9230\"
tsx packages/indexer-agent/src/index.ts start"
