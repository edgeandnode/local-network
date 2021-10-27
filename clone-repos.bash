#!/usr/bin/env bash
source prelude.bash

repos="\
  edgeandnode/gateway
  edgeandnode/indexer-selection
  edgeandnode/subgraph-studio
  graphprotocol/common-ts
  graphprotocol/contracts
  graphprotocol/cost-model
  graphprotocol/graph-network-subgraph
  graphprotocol/graph-node
  graphprotocol/indexer"

for repo in ${repos}; do
  if [ -d "projects/${repo}" ]; then continue; fi
  git clone "git@github.com:${repo}" "projects/${repo}"
done
