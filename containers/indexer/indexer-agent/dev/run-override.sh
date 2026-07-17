#!/bin/bash
set -xeu
. /opt/config/.env

. /opt/shared/lib.sh

token_address=$(contract_addr L2GraphToken.address horizon)
staking_address=$(contract_addr HorizonStaking.address horizon)
indexer_stake="$(cast call "--rpc-url=http://chain:${CHAIN_RPC_PORT}" \
  "${staking_address}" 'getStake(address) (uint256)' "${RECEIVER_ADDRESS}")"
echo "indexer_stake=${indexer_stake}"
if [ "${indexer_stake}" = "0" ]; then
  # transfer ETH to receiver
  cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
    --value=1ether "${RECEIVER_ADDRESS}"
  # transfer 100,000 GRT to receiver
  cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
    "${token_address}" 'transfer(address,uint256)' "${RECEIVER_ADDRESS}" '100000000000000000000000'
  # stake required GRT for indexer registration
  cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--private-key=${RECEIVER_SECRET}" \
    "${token_address}" 'approve(address,uint256)' "${staking_address}" '100000000000000000000000'
  cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--private-key=${RECEIVER_SECRET}" \
    "${staking_address}" 'stake(uint256)' '100000000000000000000000'
fi

export INDEXER_AGENT_HORIZON_ADDRESS_BOOK=/opt/config/horizon.json
export INDEXER_AGENT_SUBGRAPH_SERVICE_ADDRESS_BOOK=/opt/config/subgraph-service.json
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
# indexing-payments subgraph is deployed by subgraph-deploy; the agent crashes on
# startup (undefined .status) if this is unset. TAP subgraph URL likewise must be
# defined or the agent crashes; point it at a stale 404 endpoint (DIPs doesn't use it).
export INDEXER_AGENT_INDEXING_PAYMENTS_SUBGRAPH_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/indexing-payments"
export INDEXER_AGENT_TAP_SUBGRAPH_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/semiotic/tap"
export INDEXER_AGENT_TAP_ADDRESS_BOOK=/opt/config/tap-contracts.json
export INDEXER_AGENT_NETWORK_PROVIDER="http://chain:${CHAIN_RPC_PORT}"
export INDEXER_AGENT_MNEMONIC="${INDEXER_MNEMONIC}"
export INDEXER_AGENT_POSTGRES_DATABASE=indexer_components_1
export INDEXER_AGENT_POSTGRES_HOST=postgres
export INDEXER_AGENT_POSTGRES_PORT="${POSTGRES_PORT}"
export INDEXER_AGENT_POSTGRES_USERNAME=postgres
export INDEXER_AGENT_POSTGRES_PASSWORD=
export INDEXER_AGENT_PUBLIC_INDEXER_URL="http://indexer-service:${INDEXER_SERVICE_PORT}"
export INDEXER_AGENT_MAX_PROVISION_INITIAL_SIZE=200000
export INDEXER_AGENT_CONFIRMATION_BLOCKS=1
export INDEXER_AGENT_LOG_LEVEL=trace

# DIPs: enable the agent's on-chain accept path when RecurringCollector is deployed
# (mirrors run.sh). Without it the agent never polls pending_rca_proposals, so every
# offer expires. This block is required for the DIPs dev workflow to work at all.
recurring_collector=$(contract_addr RecurringCollector.address horizon 2>/dev/null) || recurring_collector=""
if [ -n "$recurring_collector" ]; then
  # Pin the indexing-payments subgraph offchain so reconcileDeployments doesn't
  # pause it (the indexer has no allocation for it). Poll for it (up to 3m).
  echo "Waiting for indexing-payments subgraph..."
  INDEXING_PAYMENTS_DEPLOYMENT=""
  for _ip_attempt in $(seq 1 36); do
    INDEXING_PAYMENTS_DEPLOYMENT=$(curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/indexing-payments" \
      -H 'content-type: application/json' \
      -d '{"query":"{ _meta { deployment } }"}' 2>/dev/null \
      | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['_meta']['deployment'])" 2>/dev/null || true)
    [ -n "${INDEXING_PAYMENTS_DEPLOYMENT}" ] && break
    [ $((_ip_attempt % 6)) -eq 0 ] && echo "  still waiting for indexing-payments subgraph (attempt ${_ip_attempt}/36)..."
    sleep 5
  done
  if [ -n "${INDEXING_PAYMENTS_DEPLOYMENT}" ]; then
    echo "Adding indexing-payments (${INDEXING_PAYMENTS_DEPLOYMENT}) to offchain subgraphs"
    export INDEXER_AGENT_OFFCHAIN_SUBGRAPHS="${INDEXING_PAYMENTS_DEPLOYMENT}"
  else
    echo "WARNING: indexing-payments subgraph not found after 3m — DIPs accept path will stall"
  fi

  echo "Enabling DIPs (RecurringCollector=${recurring_collector})"
  export INDEXER_AGENT_ENABLE_DIPS=true
  export INDEXER_AGENT_DIPS_EPOCHS_MARGIN=1
  export INDEXER_AGENT_DIPPER_ENDPOINT="http://dipper:${DIPPER_INDEXER_RPC_PORT}"
  export INDEXER_AGENT_DIPS_ALLOCATION_AMOUNT=1
  export INDEXER_AGENT_DIPS_COLLECTION_TARGET=1
  export INDEXER_AGENT_POLLING_INTERVAL=15000
fi

cd /opt/indexer-agent-source-root

nodemon --watch . \
--ext ts \
--legacy-watch \
--delay 4 \
--verbose \
--exec "
NODE_OPTIONS=\"--inspect=0.0.0.0:9230\"
tsx packages/indexer-agent/src/index.ts start"

