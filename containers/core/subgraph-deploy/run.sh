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
  npx graph codegen --output-dir src/types/
  npx graph create graph-network --node="http://graph-node:${GRAPH_NODE_ADMIN_PORT}"
  npx graph deploy graph-network --node="http://graph-node:${GRAPH_NODE_ADMIN_PORT}" --ipfs="http://ipfs:${IPFS_RPC_PORT}" --version-label=v0.0.1
  echo "==== Network subgraph done ===="
}

deploy_tap() {
  echo "==== TAP subgraph ===="
  if curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/semiotic/tap" \
    -H 'content-type: application/json' \
    -d '{"query": "{ _meta { deployment } }" }' | grep -q "_meta"
  then
    echo "SKIP: TAP subgraph already deployed"
    return
  fi

  # Horizon moved signer authorization from PaymentsEscrow to GraphTallyCollector
  escrow=$(contract_addr GraphTallyCollector.address horizon)

  cd /opt/timeline-aggregation-protocol-subgraph
  sed -i "s/127.0.0.1:5001/ipfs:${IPFS_RPC_PORT}/g" package.json
  sed -i "s/127.0.0.1:8020/graph-node:${GRAPH_NODE_ADMIN_PORT}/g" package.json
  yq ".dataSources[].source.address=\"${escrow}\"" -i subgraph.yaml
  yq ".dataSources[].network |= \"hardhat\"" -i subgraph.yaml

  # Horizon renamed events: AuthorizeSigner -> SignerAuthorized,
  # RevokeAuthorizedSigner -> SignerRevoked, and swapped the parameter order
  # from (signer, sender) to (authorizer, signer). Patch all three layers.

  # 1. subgraph.yaml event signatures
  sed -i 's/AuthorizeSigner(indexed address,indexed address)/SignerAuthorized(indexed address,indexed address)/g' subgraph.yaml
  sed -i 's/RevokeAuthorizedSigner(indexed address,indexed address)/SignerRevoked(indexed address,indexed address)/g' subgraph.yaml

  # 2. ABI: rename events and swap parameter order so codegen accessors match
  #    the mapping code (event.params.signer = actual signer, event.params.sender = authorizer)
  node -e "
const fs = require('fs');
const abi = JSON.parse(fs.readFileSync('abis/Escrow.abi.json'));
for (const e of abi) {
  if (e.type !== 'event') continue;
  if (e.name === 'AuthorizeSigner') {
    e.name = 'SignerAuthorized';
    e.inputs = [
      {indexed: true, internalType: 'address', name: 'sender', type: 'address'},
      {indexed: true, internalType: 'address', name: 'signer', type: 'address'}
    ];
  } else if (e.name === 'RevokeAuthorizedSigner') {
    e.name = 'SignerRevoked';
    e.inputs = [
      {indexed: true, internalType: 'address', name: 'sender', type: 'address'},
      {indexed: true, internalType: 'address', name: 'authorizedSigner', type: 'address'}
    ];
  }
}
fs.writeFileSync('abis/Escrow.abi.json', JSON.stringify(abi, null, 2));
"

  # 3. Mapping imports and type annotations
  sed -i 's/AuthorizeSigner, RevokeAuthorizedSigner/SignerAuthorized, SignerRevoked/g' src/mappings/escrow.ts
  sed -i 's/event: AuthorizeSigner/event: SignerAuthorized/g' src/mappings/escrow.ts
  sed -i 's/event: RevokeAuthorizedSigner/event: SignerRevoked/g' src/mappings/escrow.ts

  yarn codegen
  yarn build
  yarn create-local
  yarn deploy-local | tee deploy.txt
  deployment_id="$(grep "Build completed: " deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"
  curl -s "http://graph-node:${GRAPH_NODE_ADMIN_PORT}" \
    -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"subgraph_reassign\",\"params\":{\"node_id\":\"default\",\"ipfs_hash\":\"${deployment_id}\"}}"
  echo "==== TAP subgraph done ===="
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

  subgraph_service=$(contract_addr SubgraphService.address subgraph-service)

  cd /opt/indexing-payments-subgraph

  # Generate manifest from template with local-network addresses
  cat > /tmp/indexing-payments-config.json <<-CONF
  {
    "network": "hardhat",
    "address": "${subgraph_service}",
    "startBlock": 0
  }
CONF
  npx mustache /tmp/indexing-payments-config.json subgraph.template.yaml > subgraph.yaml
  npx graph codegen
  npx graph build
  npx graph create indexing-payments --node="http://graph-node:${GRAPH_NODE_ADMIN_PORT}"
  npx graph deploy indexing-payments --node="http://graph-node:${GRAPH_NODE_ADMIN_PORT}" --ipfs="http://ipfs:${IPFS_RPC_PORT}" --version-label=v0.1.0
  echo "==== Indexing-payments subgraph done ===="
}

# Launch all four in parallel
deploy_network &
pid_network=$!
deploy_tap &
pid_tap=$!
deploy_block_oracle &
pid_oracle=$!
deploy_indexing_payments &
pid_payments=$!

# Wait for all, fail if any fails
failed=0
wait $pid_network || { echo "FAILED: Network subgraph"; failed=1; }
wait $pid_tap || { echo "FAILED: TAP subgraph"; failed=1; }
wait $pid_oracle || { echo "FAILED: Block-oracle subgraph"; failed=1; }
wait $pid_payments || { echo "FAILED: Indexing-payments subgraph"; failed=1; }

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
