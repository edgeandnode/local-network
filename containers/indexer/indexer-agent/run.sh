#!/bin/sh
set -eu

# In test-indexer compose projects, IndexerHandle injects per-test indexer identity
# via TEST_INDEXER_* env vars. Capture them before sourcing .env (which would
# otherwise overwrite them with the production-default INDEXER_* values).
__test_indexer_address="${TEST_INDEXER_ADDRESS:-}"
__test_indexer_secret="${TEST_INDEXER_SECRET:-}"
__test_indexer_mnemonic="${TEST_INDEXER_MNEMONIC:-}"

. /opt/config/.env

[ -n "${__test_indexer_address}" ] && INDEXER_ADDRESS="${__test_indexer_address}"
[ -n "${__test_indexer_secret}" ] && INDEXER_SECRET="${__test_indexer_secret}"
[ -n "${__test_indexer_mnemonic}" ] && INDEXER_MNEMONIC="${__test_indexer_mnemonic}"

. /opt/shared/lib.sh

token_address=$(contract_addr L2GraphToken.address horizon)
staking_address=$(contract_addr HorizonStaking.address horizon)
indexer_stake="$(cast call "--rpc-url=http://chain:${CHAIN_RPC_PORT}" \
  "${staking_address}" 'getStake(address)(uint256)' "${INDEXER_ADDRESS}")"
echo "indexer_stake=${indexer_stake}"
if [ "${indexer_stake}" = "0" ]; then
  # transfer ETH to receiver
  cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
    --value=1ether "${INDEXER_ADDRESS}"
  # transfer 100,000 GRT to receiver
  cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
    "${token_address}" 'transfer(address,uint256)' "${INDEXER_ADDRESS}" '100000000000000000000000'
  # stake required GRT for indexer registration
  cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--private-key=${INDEXER_SECRET}" \
    "${token_address}" 'approve(address,uint256)' "${staking_address}" '100000000000000000000000'
  cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--private-key=${INDEXER_SECRET}" \
    "${staking_address}" 'stake(uint256)' '100000000000000000000000'
fi

# Authorize the indexer as its own operator for the SubgraphService
# This is required for attestation verification in Horizon
subgraph_service_address=$(contract_addr SubgraphService.address subgraph-service)
operator_authorized="$(cast call "--rpc-url=http://chain:${CHAIN_RPC_PORT}" \
  "${staking_address}" 'isAuthorized(address,address,address)(bool)' \
  "${INDEXER_ADDRESS}" "${INDEXER_ADDRESS}" "${subgraph_service_address}")"
echo "operator_authorized=${operator_authorized}"
if [ "${operator_authorized}" = "false" ]; then
  echo "Authorizing indexer as operator for SubgraphService..."
  cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--private-key=${INDEXER_SECRET}" \
    "${staking_address}" 'setOperator(address,address,bool)' \
    "${INDEXER_ADDRESS}" "${subgraph_service_address}" "true"
fi

export INDEXER_AGENT_HORIZON_ADDRESS_BOOK=/opt/config/horizon.json
export INDEXER_AGENT_SUBGRAPH_SERVICE_ADDRESS_BOOK=/opt/config/subgraph-service.json
export INDEXER_AGENT_EPOCH_SUBGRAPH_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/block-oracle"
export INDEXER_AGENT_GATEWAY_ENDPOINT="http://gateway:${GATEWAY_PORT}"
export INDEXER_AGENT_GRAPH_NODE_QUERY_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}"
export INDEXER_AGENT_GRAPH_NODE_ADMIN_ENDPOINT="http://graph-node:${GRAPH_NODE_ADMIN_PORT}"
export INDEXER_AGENT_GRAPH_NODE_STATUS_ENDPOINT="http://graph-node:${GRAPH_NODE_STATUS_PORT}/graphql"
export INDEXER_AGENT_IPFS_ENDPOINT="http://ipfs:${IPFS_RPC_PORT}"
export INDEXER_AGENT_INDEXER_ADDRESS="${INDEXER_ADDRESS}"
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
export INDEXER_AGENT_MAX_PROVISION_INITIAL_SIZE=200000
export INDEXER_AGENT_CONFIRMATION_BLOCKS=1
export INDEXER_AGENT_LOG_LEVEL=trace

# Tell the agent to leave protocol-infra subgraphs (indexing-payments,
# block-oracle) alone. Without this the reconciler pauses them (they have
# no allocation), which:
#   - stalls dipper's chain_listener waiting for indexing-payments events
#   - lags the block-oracle subgraph behind the chain, which makes
#     indexer-agent (and tests) time out on epoch sync.
# subgraph-deploy is a compose dependency, so the deployments exist by now.
get_deployment() {
  local name=$1
  curl -sf \
    "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/${name}" \
    -H 'content-type: application/json' \
    -d '{"query":"{ _meta { deployment } }"}' \
    | jq -r '.data._meta.deployment // empty'
}

indexing_payments_deployment=$(get_deployment indexing-payments)
block_oracle_deployment=$(get_deployment block-oracle)
if [ -z "${indexing_payments_deployment}" ]; then
  echo "ERROR: indexing-payments subgraph deployment not found — chain_listener will stall" >&2
  exit 1
fi
if [ -z "${block_oracle_deployment}" ]; then
  echo "ERROR: block-oracle subgraph deployment not found — epoch sync will lag" >&2
  exit 1
fi
echo "Marking indexing-payments (${indexing_payments_deployment}) and block-oracle (${block_oracle_deployment}) as offchain"
export INDEXER_AGENT_OFFCHAIN_SUBGRAPHS="${indexing_payments_deployment},${block_oracle_deployment}"

# The agent constructs an indexing-payments SubgraphClient unconditionally
# (Network.create:100). Without an endpoint or deployment-id, it crashes
# with "Cannot read properties of undefined (reading 'status')" before the
# management API can come up. Provide the query endpoint here regardless of
# --enable-dips so the spec is fully populated.
export INDEXER_AGENT_INDEXING_PAYMENTS_SUBGRAPH_ENDPOINT="http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/indexing-payments"

node ./dist/index.js start
