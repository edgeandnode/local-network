#!/bin/sh
set -eu
# shellcheck source=/dev/null
. /opt/config/.env

# shellcheck source=/dev/null
. /opt/shared/lib.sh

# Per-indexer overrides. The primary indexer leaves these unset and inherits
# the default identity (RECEIVER_*) and service hostnames; extras inject their
# own values via compose `environment:`. Keep names identical to tap-agent.
INDEXER_ADDRESS="${INDEXER_ADDRESS:-$RECEIVER_ADDRESS}"
INDEXER_SECRET="${INDEXER_SECRET:-$RECEIVER_SECRET}"
INDEXER_OPERATOR_MNEMONIC="${INDEXER_OPERATOR_MNEMONIC:-$INDEXER_MNEMONIC}"
INDEXER_DB_NAME="${INDEXER_DB_NAME:-indexer_components_1}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
GRAPH_NODE_HOST="${GRAPH_NODE_HOST:-graph-node}"
PROTOCOL_GRAPH_NODE_HOST="${PROTOCOL_GRAPH_NODE_HOST:-graph-node}"
POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
INDEXER_SVC_HOST="${INDEXER_SVC_HOST:-indexer-service}"

token_address=$(contract_addr L2GraphToken.address horizon)
staking_address=$(contract_addr HorizonStaking.address horizon)
indexer_stake="$(cast call "--rpc-url=http://chain:${CHAIN_RPC_PORT}" \
  "${staking_address}" 'getStake(address) (uint256)' "${INDEXER_ADDRESS}")"
echo "indexer_stake=${indexer_stake}"
if [ "${indexer_stake}" = "0" ]; then
  # transfer ETH to indexer
  cast send "--rpc-url=http://chain:${CHAIN_RPC_PORT}" --confirmations=0 "--mnemonic=${MNEMONIC}" \
    --value=1ether "${INDEXER_ADDRESS}"
  # transfer 100,000 GRT to indexer
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
# Stub address book — see graph-contracts/run.sh for shape rationale. Required
# by @semiotic-labs/tap-contracts-bindings, which has no chainId 1337 baked in.
export INDEXER_AGENT_TAP_ADDRESS_BOOK=/opt/config/tap-contracts.json
# Protocol subgraphs (network, epoch, indexing-payments, tap) live on the
# primary's graph-node — extras query the same endpoints. The agent's own
# graph-node admin/query/status endpoints point at GRAPH_NODE_HOST (the
# indexer's own graph-node, which equals primary for the primary indexer).
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
# indexing-payments subgraph is deployed by subgraph-deploy.
export INDEXER_AGENT_INDEXING_PAYMENTS_SUBGRAPH_ENDPOINT="http://${PROTOCOL_GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/indexing-payments"
# TAP subgraph is no longer deployed on this branch (TAP escrow consolidated
# into Horizon). The agent still has unconditional code paths for TapSubgraph
# that crash when the URL is undefined, so we point at a stale endpoint that
# returns 404. The agent starts; TAP query-fee paths return errors gracefully.
# DIPs end-to-end testing does not exercise this path.
export INDEXER_AGENT_TAP_SUBGRAPH_ENDPOINT="http://${PROTOCOL_GRAPH_NODE_HOST}:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/semiotic/tap"
export INDEXER_AGENT_NETWORK_PROVIDER="http://chain:${CHAIN_RPC_PORT}"
export INDEXER_AGENT_MNEMONIC="${INDEXER_OPERATOR_MNEMONIC}"
export INDEXER_AGENT_POSTGRES_DATABASE="${INDEXER_DB_NAME}"
export INDEXER_AGENT_POSTGRES_HOST="${POSTGRES_HOST}"
export INDEXER_AGENT_POSTGRES_PORT="${POSTGRES_PORT}"
export INDEXER_AGENT_POSTGRES_USERNAME=postgres
export INDEXER_AGENT_POSTGRES_PASSWORD=
export INDEXER_AGENT_PUBLIC_INDEXER_URL="http://${INDEXER_SVC_HOST}:${INDEXER_SERVICE_PORT}"
export INDEXER_AGENT_MAX_PROVISION_INITIAL_SIZE=200000
export INDEXER_AGENT_CONFIRMATION_BLOCKS=1
export INDEXER_AGENT_LOG_LEVEL=trace

node ./dist/index.js start
