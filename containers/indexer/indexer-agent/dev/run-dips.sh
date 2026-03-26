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

# --- Start yarn install immediately (no deps needed) ---
(
  cd /opt/indexer-agent-source-root
  flock -x 200
  if [ ! -f node_modules/.yarn-install-stamp ] || [ yarn.lock -nt node_modules/.yarn-install-stamp ]; then
    yarn install --frozen-lockfile
    touch node_modules/.yarn-install-stamp
  fi
) 200>/opt/indexer-agent-source-root/.yarn-install.lock &
INSTALL_PID=$!

# --- Wait for dependencies in parallel with install ---
wait_for_config
wait_for_rpc

token_address=$(contract_addr L2GraphToken.address horizon)
staking_address=$(contract_addr HorizonStaking.address horizon)

if [ "${INDEXER_ADDRESS}" = "${RECEIVER_ADDRESS}" ]; then
  # Primary indexer: self-stake using RECEIVER's own key (no nonce collision
  # with ACCOUNT0). Idempotent -- skips if already staked.
  indexer_stake="$(cast call "--rpc-url=http://chain:${CHAIN_RPC_PORT}" \
    "${staking_address}" 'getStake(address) (uint256)' "${INDEXER_ADDRESS}")"
  if [ "${indexer_stake}" = "0" ]; then
    echo "Staking primary indexer ${INDEXER_ADDRESS}..."
    cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
      --value=1ether "${INDEXER_ADDRESS}"
    cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
      "${token_address}" 'transfer(address,uint256)' "${INDEXER_ADDRESS}" '100000000000000000000000'
    cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--private-key=${INDEXER_SECRET}" \
      "${token_address}" 'approve(address,uint256)' "${staking_address}" '100000000000000000000000'
    cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--private-key=${INDEXER_SECRET}" \
      "${staking_address}" 'stake(uint256)' '100000000000000000000000'
    echo "Primary indexer staked"
  else
    echo "Primary indexer already staked: ${indexer_stake}"
  fi
else
  # Extra indexers: wait for start-indexing-extra to stake them on-chain.
  echo "Waiting for indexer ${INDEXER_ADDRESS} to be staked..."
  _stake_attempt=0
  while [ "$_stake_attempt" -lt 90 ]; do
    _stake_attempt=$((_stake_attempt + 1))
    indexer_stake="$(cast call "--rpc-url=http://chain:${CHAIN_RPC_PORT}" \
      "${staking_address}" 'getStake(address) (uint256)' "${INDEXER_ADDRESS}" 2>/dev/null || echo "0")"
    if [ "${indexer_stake}" != "0" ]; then
      echo "Indexer staked: ${indexer_stake}"
      break
    fi
    if [ $((_stake_attempt % 12)) -eq 0 ]; then
      echo "  still waiting for staking (attempt ${_stake_attempt}/90)..."
    fi
    sleep 5
  done
  if [ "${indexer_stake}" = "0" ]; then
    echo "ERROR: Indexer ${INDEXER_ADDRESS} not staked after 450s"
    exit 1
  fi
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

# Keep the indexing-payments subgraph deployed (dipper's chain_listener reads it).
# Without this, reconcileDeployments pauses it because it has no allocation.
# Wait up to 3 minutes -- subgraph-deploy runs in parallel and may not finish yet.
echo "Waiting for indexing-payments subgraph..."
INDEXING_PAYMENTS_DEPLOYMENT=""
for _ip_attempt in $(seq 1 36); do
  INDEXING_PAYMENTS_DEPLOYMENT=$(curl -s "http://${PROTOCOL_GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/indexing-payments" \
    -H 'content-type: application/json' \
    -d '{"query":"{ _meta { deployment } }"}' 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['_meta']['deployment'])" 2>/dev/null || true)
  if [ -n "${INDEXING_PAYMENTS_DEPLOYMENT}" ]; then
    break
  fi
  [ $((_ip_attempt % 6)) -eq 0 ] && echo "  still waiting for indexing-payments subgraph (attempt ${_ip_attempt}/36)..."
  sleep 5
done
if [ -n "${INDEXING_PAYMENTS_DEPLOYMENT}" ]; then
  echo "Adding indexing-payments (${INDEXING_PAYMENTS_DEPLOYMENT}) to offchain subgraphs"
  export INDEXER_AGENT_OFFCHAIN_SUBGRAPHS="${INDEXING_PAYMENTS_DEPLOYMENT}"
else
  echo "WARNING: indexing-payments subgraph not found after 3m -- chain_listener will stall"
fi

# DIPs configuration
export INDEXER_AGENT_ENABLE_DIPS=true
export INDEXER_AGENT_DIPS_EPOCHS_MARGIN=1
export INDEXER_AGENT_DIPPER_ENDPOINT="http://dipper:${DIPPER_INDEXER_RPC_PORT}"
export INDEXER_AGENT_DIPS_ALLOCATION_AMOUNT=1
# Faster reconciliation for local testing (default 120s is too slow)
export INDEXER_AGENT_POLLING_INTERVAL=15000

# --- Wait for yarn install to finish ---
echo "Waiting for yarn install to complete..."
wait $INSTALL_PID
echo "Install complete"

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
