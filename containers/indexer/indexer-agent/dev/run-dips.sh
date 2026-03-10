#!/bin/bash
set -xeu
. /opt/config/.env

. /opt/shared/lib.sh

# Allow env var overrides for multi-indexer support
INDEXER_ADDRESS="${INDEXER_ADDRESS:-$RECEIVER_ADDRESS}"
INDEXER_SECRET="${INDEXER_SECRET:-$RECEIVER_SECRET}"
INDEXER_OPERATOR_MNEMONIC="${INDEXER_OPERATOR_MNEMONIC:-$INDEXER_MNEMONIC}"
INDEXER_DB_NAME="${INDEXER_DB_NAME:-indexer_components_1}"
INDEXER_SVC_HOST="${INDEXER_SVC_HOST:-indexer-service}"
GRAPH_NODE_HOST="${GRAPH_NODE_HOST:-graph-node}"
PROTOCOL_GRAPH_NODE_HOST="${PROTOCOL_GRAPH_NODE_HOST:-graph-node}"
POSTGRES_HOST="${POSTGRES_HOST:-postgres}"

wait_for_rpc

# Verify this indexer is staked (registration handled by start-indexing or start-indexing-extra)
staking_address=$(contract_addr HorizonStaking.address horizon)
indexer_stake="$(cast call "--rpc-url=http://chain:${CHAIN_RPC_PORT}" \
  "${staking_address}" 'getStake(address) (uint256)' "${INDEXER_ADDRESS}")"
echo "indexer_stake=${indexer_stake}"
if [ "${indexer_stake}" = "0" ]; then
  echo "ERROR: Indexer ${INDEXER_ADDRESS} has no stake. Run start-indexing-extra first."
  exit 1
fi

export INDEXER_AGENT_HORIZON_ADDRESS_BOOK=/opt/config/horizon.json
export INDEXER_AGENT_SUBGRAPH_SERVICE_ADDRESS_BOOK=/opt/config/subgraph-service.json
export INDEXER_AGENT_TAP_ADDRESS_BOOK=/opt/config/tap-contracts.json
export INDEXER_AGENT_EPOCH_SUBGRAPH_ENDPOINT="http://${PROTOCOL_GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/block-oracle"
export INDEXER_AGENT_GATEWAY_ENDPOINT="http://gateway:${GATEWAY_PORT}"
export INDEXER_AGENT_GRAPH_NODE_QUERY_ENDPOINT="http://${GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}"
export INDEXER_AGENT_GRAPH_NODE_ADMIN_ENDPOINT="http://${GRAPH_NODE_HOST}:${GRAPH_NODE_ADMIN_PORT}"
export INDEXER_AGENT_GRAPH_NODE_STATUS_ENDPOINT="http://${GRAPH_NODE_HOST}:${GRAPH_NODE_STATUS_PORT}/graphql"
export INDEXER_AGENT_IPFS_ENDPOINT="http://ipfs:${IPFS_RPC_PORT}"
export INDEXER_AGENT_INDEXER_ADDRESS="${INDEXER_ADDRESS}"
export INDEXER_AGENT_INDEXER_MANAGEMENT_PORT="${INDEXER_MANAGEMENT_PORT}"
export INDEXER_AGENT_INDEX_NODE_IDS=default
export INDEXER_AGENT_INDEXER_GEO_COORDINATES="1 1"
export INDEXER_AGENT_VOUCHER_REDEMPTION_THRESHOLD=0.01
export INDEXER_AGENT_NETWORK_SUBGRAPH_ENDPOINT="http://${PROTOCOL_GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network"
export INDEXER_AGENT_NETWORK_PROVIDER="http://chain:${CHAIN_RPC_PORT}"
export INDEXER_AGENT_MNEMONIC="${INDEXER_OPERATOR_MNEMONIC}"
export INDEXER_AGENT_POSTGRES_DATABASE="${INDEXER_DB_NAME}"
export INDEXER_AGENT_POSTGRES_HOST="${POSTGRES_HOST}"
export INDEXER_AGENT_POSTGRES_PORT="${POSTGRES_PORT}"
export INDEXER_AGENT_POSTGRES_USERNAME=postgres
export INDEXER_AGENT_POSTGRES_PASSWORD=
export INDEXER_AGENT_PUBLIC_INDEXER_URL="http://${INDEXER_SVC_HOST}:${INDEXER_SERVICE_PORT}"
export INDEXER_AGENT_TAP_SUBGRAPH_ENDPOINT="http://${PROTOCOL_GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/semiotic/tap"
export INDEXER_AGENT_MAX_PROVISION_INITIAL_SIZE=200000
export INDEXER_AGENT_CONFIRMATION_BLOCKS=1
export INDEXER_AGENT_LOG_LEVEL=trace

# DIPs configuration
export INDEXER_AGENT_ENABLE_DIPS=true
export INDEXER_AGENT_DIPS_EPOCHS_MARGIN=1
export INDEXER_AGENT_DIPPER_ENDPOINT="http://dipper:${DIPPER_INDEXER_RPC_PORT}"
export INDEXER_AGENT_DIPS_ALLOCATION_AMOUNT=1

cd /opt/indexer-agent-source-root
(
  flock -x 200
  if [ ! -f node_modules/.yarn-install-stamp ] || [ yarn.lock -nt node_modules/.yarn-install-stamp ]; then
    yarn install --frozen-lockfile
    touch node_modules/.yarn-install-stamp
  fi
) 200>/opt/indexer-agent-source-root/.yarn-install.lock
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

MAX_RETRIES=30
RETRY_DELAY=10
attempt=0
while [ $attempt -lt $MAX_RETRIES ]; do
  attempt=$((attempt + 1))
  echo "=== Starting indexer-agent (attempt $attempt/$MAX_RETRIES) ==="
  NODE_OPTIONS="--inspect=0.0.0.0:9230" \
    tsx packages/indexer-agent/src/index.ts start && break
  echo "Agent exited with code $?, retrying in ${RETRY_DELAY}s..."
  sleep $RETRY_DELAY
done

if [ $attempt -ge $MAX_RETRIES ]; then
  echo "Agent failed after $MAX_RETRIES attempts"
  exit 1
fi
