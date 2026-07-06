#!/bin/bash
set -eu
# shellcheck source=/dev/null
. /opt/config/.env
# shellcheck source=/dev/null
. /opt/shared/lib.sh

t0=$SECONDS
elapsed() { echo "[+$((SECONDS - t0))s] $*"; }

# ============================================================
# Deploy subgraphs to graph-node (in parallel)
# ============================================================

deploy_network() {
  echo "==== Network subgraph ===="
  if curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network" \
    -H 'content-type: application/json' \
    -d '{"query": "{ _meta { deployment } }" }' | grep -q "_meta"
  then
    echo "SKIP: Network subgraph already deployed"
    return
  fi

  # localNetworkAddressScript.ts reads from /opt/horizon.json and /opt/subgraph-service.json
  cp /opt/config/horizon.json /opt/horizon.json
  cp /opt/config/subgraph-service.json /opt/subgraph-service.json

  cd /opt/graph-network-subgraph
  npx ts-node config/localNetworkAddressScript.ts
  npx mustache ./config/generatedAddresses.json ./config/addresses.template.ts > ./config/addresses.ts
  npx mustache ./config/generatedAddresses.json subgraph.template.yaml > subgraph.yaml
  npx graph codegen --output-dir src/types/
  npx graph create graph-network --node="http://graph-node:${GRAPH_NODE_ADMIN_PORT}"
  npx graph deploy graph-network --node="http://graph-node:${GRAPH_NODE_ADMIN_PORT}" --ipfs="http://ipfs:${IPFS_RPC_PORT}" --version-label=v0.0.1 | tee deploy.txt
  # graph-cli does not always assign a freshly deployed subgraph to the
  # default node -- without an explicit reassign, graph-node leaves the
  # deployment unscheduled and the subgraph never starts indexing.
  deployment_id="$(grep "Build completed: " deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"
  curl -s "http://graph-node:${GRAPH_NODE_ADMIN_PORT}" \
    -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"subgraph_reassign\",\"params\":{\"node_id\":\"default\",\"ipfs_hash\":\"${deployment_id}\"}}"
  echo "==== Network subgraph done ===="
}

deploy_block_oracle() {
  echo "==== Block-oracle subgraph ===="
  if curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/block-oracle" \
    -H 'content-type: application/json' \
    -d '{"query": "{ _meta { deployment } }" }' | grep -q "_meta"
  then
    echo "SKIP: Block-oracle subgraph already deployed"
    return
  fi

  graph_epoch_manager=$(contract_addr EpochManager.address horizon)
  data_edge=$(contract_addr DataEdge block-oracle)

  cd /opt/block-oracle/packages/subgraph

  yq -i ".epochManager |= \"${graph_epoch_manager}\"" config/local.json
  yq -i ".permissionList[0].address |= \"0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266\"" config/local.json
  yq -i ".hardhat.DataEdge.address |= \"${data_edge}\"" networks.json

  pnpm prepare
  pnpm prep:local
  pnpm codegen
  npx graph build --network hardhat
  yq -i ".dataSources[0].network |= \"hardhat\"" subgraph.yaml
  npx graph create block-oracle --node="http://graph-node:${GRAPH_NODE_ADMIN_PORT}"
  npx graph deploy block-oracle --node="http://graph-node:${GRAPH_NODE_ADMIN_PORT}" --ipfs="http://ipfs:${IPFS_RPC_PORT}" --version-label 'v0.0.1' | tee deploy.txt
  deployment_id="$(grep "Build completed: " deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"
  echo "deployed block-oracle to deployment_id: ${deployment_id}"
  curl -s "http://graph-node:${GRAPH_NODE_ADMIN_PORT}" \
    -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"subgraph_reassign\",\"params\":{\"node_id\":\"default\",\"ipfs_hash\":\"${deployment_id}\"}}"
  echo "==== Block-oracle subgraph done ===="
}

deploy_indexing_payments() {
  echo "==== Indexing-payments subgraph ===="

  # Only deploy when DIPs contracts are present (RecurringCollector in horizon.json)
  if ! contract_addr RecurringCollector.address horizon >/dev/null 2>&1; then
    echo "SKIP: RecurringCollector not deployed (DIPs not enabled)"
    return
  fi

  if curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/indexing-payments" \
    -H 'content-type: application/json' \
    -d '{"query": "{ _meta { deployment } }" }' | grep -q "_meta"
  then
    echo "SKIP: Indexing-payments subgraph already deployed"
    return
  fi

  # Wait for both config files before reading addresses. In the parallel
  # deploy path, horizon.json may be partially written when we land here.
  wait_for_config 300

  subgraph_service=$(contract_addr SubgraphService.address subgraph-service)
  recurring_collector=$(contract_addr RecurringCollector.address horizon)
  recurring_agreement_manager=$(contract_addr RecurringAgreementManager.address issuance)
  echo "deploy_indexing_payments: subgraph_service=${subgraph_service} recurring_collector=${recurring_collector} recurring_agreement_manager=${recurring_agreement_manager}"

  if [ -z "${subgraph_service}" ] || [ -z "${recurring_collector}" ] || [ -z "${recurring_agreement_manager}" ]; then
    echo "ERROR: deploy_indexing_payments got empty addresses, bailing"
    return 1
  fi

  cd /opt/indexing-payments-subgraph

  # Generate manifest from template. The subgraph indexes SubgraphService,
  # RecurringCollector, and RecurringAgreementManager (its role grants drive
  # the indexer-service DIPs trust gate).
  cat > /tmp/indexing-payments-config.json <<-CONF
  {
    "network": "hardhat",
    "subgraphServiceAddress": "${subgraph_service}",
    "recurringCollectorAddress": "${recurring_collector}",
    "recurringAgreementManagerAddress": "${recurring_agreement_manager}",
    "startBlock": 0
  }
CONF
  npx mustache /tmp/indexing-payments-config.json subgraph.template.yaml > subgraph.yaml
  npx graph codegen
  npx graph build
  npx graph create indexing-payments --node="http://graph-node:${GRAPH_NODE_ADMIN_PORT}"
  npx graph deploy indexing-payments --node="http://graph-node:${GRAPH_NODE_ADMIN_PORT}" --ipfs="http://ipfs:${IPFS_RPC_PORT}" --version-label=v0.1.0 | tee deploy.txt
  # Reassign like deploy_network/deploy_block_oracle: without this graph-node
  # leaves the deployment unassigned, the subgraph never starts, and dipper's
  # chain_listener blocks on a stalled subgraph.
  deployment_id="$(grep "Build completed: " deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"
  curl -s "http://graph-node:${GRAPH_NODE_ADMIN_PORT}" \
    -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"subgraph_reassign\",\"params\":{\"node_id\":\"default\",\"ipfs_hash\":\"${deployment_id}\"}}"
  echo "==== Indexing-payments subgraph done ===="
}

# Launch all three in parallel
deploy_network &
pid_network=$!
deploy_block_oracle &
pid_oracle=$!
deploy_indexing_payments &
pid_payments=$!

# Wait for all, fail if any fails
failed=0
wait $pid_network || { echo "FAILED: Network subgraph"; failed=1; }
wait $pid_oracle || { echo "FAILED: Block-oracle subgraph"; failed=1; }
wait $pid_payments || { echo "FAILED: Indexing-payments subgraph"; failed=1; }

if [ "$failed" -ne 0 ]; then
  echo "One or more subgraph deployments failed"
  exit 1
fi

elapsed "==== All subgraphs deployed ===="

# Wait for network subgraph to sync graphNetwork entity (indexer-service needs
# it at startup to initialize the dispute manager).
elapsed "Waiting for network subgraph to sync graphNetwork entity..."
until curl -sf "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network" \
  -H 'content-type: application/json' \
  -d '{"query": "{ graphNetwork(id: \"1\") { disputeManager } }"}' \
  | grep -q '"disputeManager"'
do
  sleep 2
done
elapsed "==== Network subgraph ready ===="
