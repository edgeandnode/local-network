#!/bin/bash
set -eu
. /opt/config/.env
. /opt/shared/lib.sh

t0=$SECONDS
elapsed() { echo "[+$((SECONDS - t0))s] $*"; }

# -- Idempotency: skip everything if allocations already active --
# Still check curation signal — may be missing after volume cleanup.
if curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network" \
  -H 'content-type: application/json' \
  -d '{"query": "{ allocations(where:{status:Active}) { indexer { id } } }" }' \
  | grep -qi "${RECEIVER_ADDRESS}"
then
  echo "Active allocations found, ensuring curation signal on all deployments..."

  graph_token=$(contract_addr L2GraphToken.address horizon)
  curation=$(contract_addr L2Curation.address horizon)
  signal_per_dep="1000000000000000000000"  # 1000 GRT per deployment
  added=0

  for subgraph_name in graph-network block-oracle semiotic/tap; do
    dep_id="$(curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/${subgraph_name}" \
      -H 'content-type: application/json' \
      -d '{"query": "{ _meta { deployment } }" }' | jq -r '.data._meta.deployment')"
    [ -z "$dep_id" ] || [ "$dep_id" = "null" ] && continue
    dep_hex="$(curl -s -X POST "http://ipfs:${IPFS_RPC_PORT}/api/v0/cid/format?arg=${dep_id}&b=base16" | jq -r '.Formatted')"
    dep_hex="${dep_hex#f01701220}"

    existing=$(cast call --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
      "${curation}" "getCurationPoolSignal(bytes32)(uint256)" "0x${dep_hex}" 2>/dev/null | awk '{print $1}')
    if [ "${existing:-0}" != "0" ]; then
      echo "  ${subgraph_name}: signal present (${existing})"
      continue
    fi

    echo "  ${subgraph_name}: adding signal..."
    cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 --mnemonic="${MNEMONIC}" \
      "${graph_token}" "approve(address,uint256)" "${curation}" "${signal_per_dep}"
    cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 --mnemonic="${MNEMONIC}" \
      "${curation}" "mint(bytes32,uint256,uint256)" "0x${dep_hex}" "${signal_per_dep}" "0"
    added=$((added + 1))
  done
  [ $added -gt 0 ] && echo "Added signal to ${added} deployment(s)" || echo "All deployments have signal"
  exit 0
fi

# ============================================================
# Configure indexing
# ============================================================

# -- Wait for indexer-agent to be ready --
elapsed "Waiting for indexer-agent..."
while ! curl -sf "http://indexer-agent:${INDEXER_MANAGEMENT_PORT}/" > /dev/null 2>&1; do
  sleep 2
done
elapsed "indexer-agent ready"

# -- Get deployment IDs from graph-node (wait for subgraphs to sync) --
get_deployment() {
  local name="$1"
  local result=""
  while [ -z "$result" ] || [ "$result" = "null" ]; do
    result="$(curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/${name}" \
      -H 'content-type: application/json' \
      -d '{"query": "{ _meta { deployment } }" }' | jq -r '.data._meta.deployment')"
    if [ -z "$result" ] || [ "$result" = "null" ]; then
      echo "Waiting for ${name} subgraph to sync..." >&2
      sleep 2
    fi
  done
  printf '%s' "$result"
}

network_deployment="$(get_deployment graph-network)"
block_oracle_deployment="$(get_deployment block-oracle)"
tap_deployment="$(get_deployment semiotic/tap)"

elapsed "network_deployment=${network_deployment}"
elapsed "block_oracle_deployment=${block_oracle_deployment}"
elapsed "tap_deployment=${tap_deployment}"

# -- Publish subgraphs to GNS (required for allocations) --
subgraph_count=$(curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network" \
  -H 'content-type: application/json' \
  -d '{"query": "{ subgraphs { id } }" }' | jq '.data.subgraphs | length // 0')
if [ "${subgraph_count:-0}" -ge 3 ]; then
  echo "Subgraphs already published to GNS (count: $subgraph_count)"
else
  gns=$(contract_addr L2GNS.address subgraph-service)
  all_dep_hexes=""
  for dep_name in network tap block_oracle; do
    eval dep_id=\$${dep_name}_deployment
    dep_hex="$(curl -s -X POST "http://ipfs:${IPFS_RPC_PORT}/api/v0/cid/format?arg=${dep_id}&b=base16" | jq -r '.Formatted')"
    dep_hex="${dep_hex#f01701220}"
    echo "Publishing ${dep_name}: ${dep_id} -> 0x${dep_hex}"
    cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 --mnemonic="${MNEMONIC}" \
      "${gns}" 'publishNewSubgraph(bytes32,bytes32,bytes32)' \
      "0x${dep_hex}" \
      '0x0000000000000000000000000000000000000000000000000000000000000000' \
      '0x0000000000000000000000000000000000000000000000000000000000000000'
    all_dep_hexes="${all_dep_hexes} ${dep_hex}"
  done
  elapsed "All subgraphs published to GNS"

  # -- Add curation signal so RewardsManager distributes rewards --
  # Without curation signal, accRewardsPerSignal stays 0 and no rewards flow.
  # Signal ALL deployments so any allocation can earn rewards.
  graph_token=$(contract_addr L2GraphToken.address horizon)
  curation=$(contract_addr L2Curation.address horizon)
  signal_per_dep="1000000000000000000000"  # 1000 GRT per deployment

  for dep_hex in ${all_dep_hexes}; do
    elapsed "Adding curation signal to 0x${dep_hex}..."
    total_approve="3000000000000000000000"  # 3000 GRT total (enough for all)
    cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 --mnemonic="${MNEMONIC}" \
      "${graph_token}" "approve(address,uint256)" "${curation}" "${total_approve}"
    cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 --mnemonic="${MNEMONIC}" \
      "${curation}" "mint(bytes32,uint256,uint256)" "0x${dep_hex}" "${signal_per_dep}" "0"
  done
  elapsed "Curation signal added to all deployments"
fi

# -- Set indexing rules (tells indexer-agent to allocate) --
graph-indexer indexer connect "http://indexer-agent:${INDEXER_MANAGEMENT_PORT}"
graph-indexer indexer --network=hardhat rules set "${network_deployment}" decisionBasis always -o json
graph-indexer indexer --network=hardhat rules set "${block_oracle_deployment}" decisionBasis always -o json
graph-indexer indexer --network=hardhat rules set "${tap_deployment}" decisionBasis always -o json

# -- Resume subgraphs that may have been paused by indexer-agent --
elapsed "Resuming subgraphs..."
for dep in "${network_deployment}" "${block_oracle_deployment}" "${tap_deployment}"; do
  curl -s -X POST "http://graph-node:${GRAPH_NODE_ADMIN_PORT}/" -H 'content-type: application/json' \
    -d "{\"jsonrpc\": \"2.0\", \"method\": \"subgraph_resume\", \"params\": {\"deployment\": \"${dep}\"}, \"id\": 1}"
done

# -- Wait for indexer-agent to create allocations --
elapsed "Waiting for allocations..."
while true; do
  output=$(graph-indexer indexer --network=hardhat actions get -o json 2>&1) || true
  if echo "$output" | grep -q 'success'; then
    elapsed "Allocation actions succeeded"
    break
  fi
  cast rpc --rpc-url="http://chain:${CHAIN_RPC_PORT}" evm_mine > /dev/null 2>&1 || true
  sleep 2
done

# -- Wait for active allocation to appear in network subgraph --
elapsed "Waiting for active allocation in network subgraph..."
while ! curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network" \
  -H 'content-type: application/json' \
  -d '{"query": "{ allocations(where:{status:Active}) { indexer { id } } }" }' \
  | grep -qi "${RECEIVER_ADDRESS}"
do
  sleep 2
done

elapsed "Allocations active, done"
