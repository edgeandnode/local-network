#!/bin/bash
set -eu
. /opt/config/.env
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
  cat subgraph.yaml
  npx graph codegen --output-dir src/types/
  npx graph create graph-network --node="http://graph-node:${GRAPH_NODE_ADMIN_PORT}"
  npx graph deploy graph-network --node="http://graph-node:${GRAPH_NODE_ADMIN_PORT}" --ipfs="http://ipfs:${IPFS_RPC_PORT}" --version-label=v0.0.1
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

# Launch in parallel
deploy_network &
pid_network=$!
deploy_block_oracle &
pid_oracle=$!

# Wait for all, fail if any fails
failed=0
wait $pid_network || { echo "FAILED: Network subgraph"; failed=1; }
wait $pid_oracle || { echo "FAILED: Block-oracle subgraph"; failed=1; }

if [ "$failed" -ne 0 ]; then
  echo "One or more subgraph deployments failed"
  exit 1
fi

elapsed "==== All subgraphs deployed ===="

# ============================================================
# Wait for network subgraph to sync graphNetwork entity
# (indexer-service needs this at startup to initialize the dispute manager)
# ============================================================
elapsed "Waiting for network subgraph to sync graphNetwork entity..."
until curl -sf "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network" \
  -H 'content-type: application/json' \
  -d '{"query": "{ graphNetwork(id: \"1\") { disputeManager } }"}' \
  | grep -q '"disputeManager"'
do
  sleep 2
done
elapsed "==== Network subgraph ready ===="
