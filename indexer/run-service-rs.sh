#!/bin/sh
set -euf

if [ ! -d "build/graphops/indexer-service-rs" ]; then
  mkdir -p build/graphops/indexer-service-rs
  git clone git@github.com:graphops/indexer-service-rs build/graphops/indexer-service-rs --branch 'main'
fi

if [ ! -d "build/semiotic-ai/timeline-aggregation-protocol-subgraph" ]; then
  mkdir -p build/semiotic-ai/timeline-aggregation-protocol-subgraph
  git clone git@github.com:semiotic-ai/timeline-aggregation-protocol-subgraph build/semiotic-ai/timeline-aggregation-protocol-subgraph --branch 'main' --recursive
fi

. ./.env
host="${DOCKER_GATEWAY_HOST:-host.docker.internal}"

network_subgraph="$(curl "http://${host}:${CONTROLLER}/graph_subgraph_deployment")"
echo "network_subgraph=${network_subgraph}"
staking=$(cat addresses.json | jq -r '."1337".StakingExtension.address')
echo "staking=${staking}"
graph_token=$(cat addresses.json | jq -r '."1337".GraphToken.address')
echo "graph_token=${graph_token}"

cd build/semiotic-ai/timeline-aggregation-protocol-subgraph

cd tests/timeline-aggregation-protocol-contracts

yarn
forge build
cast send --rpc-url "http://${host}:${CHAIN_RPC}" --private-key "${ACCOUNT0_SECRET_KEY}" --from "${ACCOUNT0_ADDRESS}" --value "0.01ether" "${GATEWAY_SIGNER_ADDRESS}"

allocation_tracker_deployment=$(forge create --rpc-url "http://${host}:${CHAIN_RPC}" --private-key "${GATEWAY_SIGNER_SECRET_KEY}" src/AllocationIDTracker.sol:AllocationIDTracker --json)
allocation_tracker=$(echo "${allocation_tracker_deployment}" | jq -r '.deployedTo')
echo "allocation_tracker=${allocation_tracker}"

tap_verifier_deployment=$(forge create --rpc-url "http://${host}:${CHAIN_RPC}" --private-key "${GATEWAY_SIGNER_SECRET_KEY}" src/TAPVerifier.sol:TAPVerifier --constructor-args 'tapVerifier' '1.0' --json)
tap_verifier=$(echo "${tap_verifier_deployment}" | jq -r '.deployedTo')
echo "tap_verifier=${tap_verifier}"

escrow_deployment=$(forge create --rpc-url "http://${host}:${CHAIN_RPC}" --private-key "${GATEWAY_SIGNER_SECRET_KEY}" src/Escrow.sol:Escrow --constructor-args "${graph_token}" "${staking}" "${tap_verifier}" "${allocation_tracker}" 10 15 --json)
escrow=$(echo "${escrow_deployment}" | jq -r '.deployedTo')
echo "escrow=${escrow}"

cd -

# yarn add --dev @graphprotocol/graph-cli
sed -i "s+http://127.0.0.1:5001+http://${host}:${IPFS_RPC}+g" package.json
sed -i "s+http://127.0.0.1:8020+http://${host}:${GRAPH_NODE_ADMIN}+g" package.json
yq ".dataSources[].source.address=\"${escrow}\"" -i subgraph.yaml
yq ".dataSources[].network |= \"hardhat\"" -i subgraph.yaml
yarn codegen
yarn build
yarn create-local
yarn deploy-local --version-label v0.0.1 | tee subgraph-deploy.txt
subgraph_deployment="$(grep "Build completed: " subgraph-deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"
echo "subgraph_deployment=${subgraph_deployment}"

# allocation_tracker=0xd9D031C5EC43cD4F24A7bcdfe5cd4141982Ef1c4
# tap_verifier=0xA86e7bD1E348b2fA2a2485219Ea93A7f8f7a7166
# escrow=0x04aef3A7A991100251572B95728D99a0095a64cC
# subgraph_deployment=QmcUGFQEgXGyCsFkyUrRRvsm5AqSofDaTR5yXqdx9ptCFs

# cast send --private-key='0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d' '0x5d0365e8dcbd1b00fc780b206e85c9d78159a865' \
#   --value '1ether'
# cast send --private-key='0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d' '0xe982E462b094850F12AF94d21D470e21bE9D0E9C' \
#   'transfer(address,uint256)' '0x5d0365e8dcbd1b00fc780b206e85c9d78159a865' '1000000000000000000000000'
# cast send --private-key='0x3547dcc43e0deb526434d31cd798676675a1f70ddec85577df7de84c2a7d08cd' '0xe982E462b094850F12AF94d21D470e21bE9D0E9C' \
#   'approve(address,uint256)' '0x7BAFD09EA92b697cc6289351318C55e2Dd776a83' '100000000000000000000000'
# cast call --private-key='0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d' '0xe982E462b094850F12AF94d21D470e21bE9D0E9C' \
#   'balanceOf(address)' '0x5d0365e8dcbd1b00fc780b206e85c9d78159a865'
# ./build/graphprotocol/indexer/packages/indexer-cli/bin/graph-indexer \
#   --network=hardhat indexer rules prepare Qmbu24TBzhGPLu2JALfv2QDeJTHzfmFbhPMySijBpHwBSe

cd ../../graphops/indexer-service-rs
cargo build

# export RUST_BACKTRACE=full
export RUST_LOG=info,service=trace
cargo run -- \
  --client-signer-address "0x5D0365E8DCBD1b00FC780b206e85c9d78159a865" \
  --ethereum "http://${host}:${CHAIN_RPC}" \
  --escrow-subgraph-deployment ${subgraph_deployment} "10000" \
  --escrow-subgraph-endpoint "http://${host}:${GRAPH_NODE_GRAPHQL}/subgraphs/id/${subgraph_deployment}" \
  --free-query-auth-token "free-query-auth" \
  --graph-node-query-endpoint "http://${host}:${GRAPH_NODE_GRAPHQL}" \
  --graph-node-status-endpoint "http://${host}:${GRAPH_NODE_STATUS}/graphql" \
  --indexer-address "${ACCOUNT0_ADDRESS}" \
  --metrics-port "7500" \
  --mnemonic "${ACCOUNT0_MNEMONIC}" \
  --network-subgraph-endpoint "http://${host}:${GRAPH_NODE_GRAPHQL}/subgraphs/id/${network_subgraph}" \
  --port "${INDEXER_SERVICE}" \
  --postgres-database "indexer_components_0"  \
  --postgres-host "${host}" \
  --postgres-password "" \
  --postgres-port "${POSTGRES}" \
  --postgres-username "dev" \
  --receipts-verifier-chain-id 1337 \
  --receipts-verifier-address "${tap_verifier}" \
  --serve-network-subgraph
