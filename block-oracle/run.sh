#!/bin/sh
set -euf

if [ ! -d "build/graphprotocol/block-oracle" ]; then
  mkdir -p build/graphprotocol/block-oracle
  git clone git@github.com:graphprotocol/block-oracle build/graphprotocol/block-oracle --branch 'main'
fi

. ./.env
host="${DOCKER_GATEWAY_HOST:-host.docker.internal}"

cd build/graphprotocol/block-oracle/packages/contracts

sed -i "s+http://localhost:8545+http://${host}:${CHAIN_RPC}+g" hardhat.config.ts
yarn
npx hardhat run --network ganache scripts/deploy-local.ts | tee deploy.txt
contract_addr="$(grep 'contract: ' deploy.txt | awk '{print $3}')"

cp ../../../../../block-oracle/contract-init.ts ./scripts
export DATA_EDGE_CONTRACT_ADDRESS="${contract_addr}"
npx hardhat run --no-compile --network ganache ./scripts/contract-init.ts

echo "contract_addr=${contract_addr}"

cd ../subgraph

yarn
yq -i ".hardhat.DataEdge.address |= \"${contract_addr}\"" networks.json
yarn prepare
yarn prep:local
yarn codegen
npx graph build --network hardhat
npx graph create block-oracle \
  --node "http://${host}:${GRAPH_NODE_ADMIN}"
npx graph deploy block-oracle \
  --ipfs "http://${host}:${IPFS_RPC}" \
  --node "http://${host}:${GRAPH_NODE_ADMIN}" \
  --version-label 'v0.0.1' | \
  tee deploy.txt

deployment_id="$(grep "Build completed: " deploy.txt | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')"

cd ../../

epoch_manager="$(curl "http://${host}:${CONTROLLER}/graph_epoch_manager")"
export BLOCK_ORACLE_OWNER_ADDRESS="${ACCOUNT0_ADDRESS#0x}"
export BLOCK_ORACLE_OWNER_SECRET_KEY="${ACCOUNT0_SECRET_KEY#0x}"
export DATA_EDGE_CONTRACT_ADDRESS="${contract_addr#0x}"
export EPOCH_MANAGER_CONTRACT_ADDRESS="${epoch_manager#0x}"
export SUBGRAPH_URL="http://${host}:${GRAPH_NODE_GRAPHQL}/subgraphs/name/block-oracle"
export PROTOCOL_CHAIN_JRPC_URL="http://${host}:${CHAIN_RPC}"
envsubst <../../../block-oracle/config.toml >config.toml
cat config.toml
export RUST_BACKTRACE='1'
export RUST_LOG=debug
curl "http://${host}:${CONTROLLER}/block_oracle_subgraph" -d "${SUBGRAPH_URL}"
curl "http://${host}:${CONTROLLER}/block_oracle_subgraph_deployment" -d "${deployment_id}"
sleep 5 # avoid indexing delay causing a long retry delay immediately
cargo run -p block-oracle -- run config.toml
