#!/bin/sh
. ./prelude.sh

github_clone graphprotocol/graph-network-subgraph theodus/local-network

await "curl -sf localhost:${IPFS_PORT}" 22
await "curl -sf localhost:${GRAPH_NODE_STATUS_PORT}" 22
await_ready common-ts

cd build/graphprotocol/graph-network-subgraph

yalc link @graphprotocol/contracts
yalc link @graphprotocol/common-ts
yalc update
yarn --non-interactive

yarn create:local
yarn deploy:hardhat

cd -

signal_ready graph-subgraph
