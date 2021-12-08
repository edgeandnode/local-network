#!/usr/bin/env bash
source prelude.bash

repos="\
  edgeandnode/gateway
  edgeandnode/graph-gateway
  edgeandnode/indexer-selection
  edgeandnode/network-services
  edgeandnode/subgraph-studio
  graphprotocol/agora
  graphprotocol/common-ts
  graphprotocol/contracts
  graphprotocol/graph-network-subgraph
  graphprotocol/graph-node
  graphprotocol/indexer"

for repo in ${repos}; do
  if [ -d "projects/${repo}" ]; then continue; fi
  git clone "git@github.com:${repo}" "projects/${repo}"
done
