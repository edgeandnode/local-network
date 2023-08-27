#!/bin/sh
set -euf

if [ ! -d "build/graphprotocol/indexer" ]; then
  mkdir -p build/graphprotocol/indexer
  git clone git@github.com:graphprotocol/indexer build/graphprotocol/indexer --branch 'theodus/local-net'
fi

# TODO: temporary hack
if [ ! -d "build/graphprotocol/common-ts" ]; then
  mkdir -p build/graphprotocol/common-ts
  git clone git@github.com:graphprotocol/common-ts build/graphprotocol/common-ts --branch 'theodus/local-net'
fi
(cd build/graphprotocol/common-ts/ && yarn)

. ./.env
host="${DOCKER_GATEWAY_HOST:-host.docker.internal}"

curl "http://${host}:${CONTROLLER}/graph_addresses" > addresses.json

cd build/graphprotocol/indexer
yarn

cd packages/indexer-agent

network_subgraph="$(curl "http://${host}:${CONTROLLER}/graph_subgraph_deployment")"
echo "network_subgraph=${network_subgraph}"

export INDEXER_AGENT_ADDRESS_BOOK=../../../../../addresses.json
export INDEXER_AGENT_ALLOCATE_ON_NETWORK_SUBGRAPH=true
export INDEXER_AGENT_COLLECT_RECEIPTS_ENDPOINT="http://${host}:${GATEWAY}/collect-receipts"
export INDEXER_AGENT_EPOCH_SUBGRAPH_ENDPOINT="http://${host}:${GRAPH_NODE_GRAPHQL}/subgraphs/name/block-oracle"
export INDEXER_AGENT_ETHEREUM="http://${host}:${CHAIN_RPC}/"
export INDEXER_AGENT_GAS_PRICE_MAX="10"
export INDEXER_AGENT_GRAPH_NODE_QUERY_ENDPOINT="http://${host}:${GRAPH_NODE_GRAPHQL}"
export INDEXER_AGENT_GRAPH_NODE_ADMIN_ENDPOINT="http://${host}:${GRAPH_NODE_ADMIN}"
export INDEXER_AGENT_GRAPH_NODE_STATUS_ENDPOINT="http://${host}:${GRAPH_NODE_STATUS}/graphql"
export INDEXER_AGENT_INDEXER_MANAGEMENT_PORT="${INDEXER_MANAGEMENT}"
export INDEXER_AGENT_INDEXER_ADDRESS="${ACCOUNT0_ADDRESS}"
export INDEXER_AGENT_INDEXER_GEO_COORDINATES="-69.42069 69.42069"
export INDEXER_AGENT_INDEX_NODE_IDS=default
export INDEXER_AGENT_LOG_LEVEL=trace
export INDEXER_AGENT_MNEMONIC="${ACCOUNT0_MNEMONIC}"
export INDEXER_AGENT_NETWORK_SUBGRAPH_DEPLOYMENT="${network_subgraph}"
export INDEXER_AGENT_NETWORK_SUBGRAPH_ENDPOINT="http://${host}:${GRAPH_NODE_GRAPHQL}/subgraphs/id/${network_subgraph}"
export INDEXER_AGENT_POI_DISPUTE_MONITORING="false"
export INDEXER_AGENT_POI_DISPUTABLE_EPOCHS="5"
export INDEXER_AGENT_POSTGRES_DATABASE=indexer_components_0
export INDEXER_AGENT_POSTGRES_HOST="${host}"
export INDEXER_AGENT_POSTGRES_PORT="${POSTGRES}"
export INDEXER_AGENT_POSTGRES_USERNAME=dev
export INDEXER_AGENT_POSTGRES_PASSWORD=
export INDEXER_AGENT_PUBLIC_INDEXER_URL="http://${host}:${INDEXER_SERVICE}"
export INDEXER_AGENT_REBATE_CLAIM_THRESHOLD=0.00001
# export INDEXER_AGENT_REBATE_CLAIM_BATCH_THRESHOLD=0.00001
export INDEXER_AGENT_RESTAKE_REWARDS="true"
export INDEXER_AGENT_VOUCHER_REDEMPTION_BATCH_THRESHOLD=0.00001
export INDEXER_AGENT_VOUCHER_REDEMPTION_THRESHOLD=0.00001

yarn start
