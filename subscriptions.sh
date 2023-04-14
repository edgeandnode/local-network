#!/bin/sh
. ./prelude.sh

github_clone edgeandnode/subscription-payments

(cd build/edgeandnode/subscription-payments/cli && cargo build)
(cd build/edgeandnode/subscription-payments/contract && yarn)
(cd build/edgeandnode/subscription-payments/subgraph && yarn)

await "curl -sf localhost:${GRAPH_NODE_STATUS_PORT} > /dev/null" 22
await "curl -sf localhost:${INDEXER_AGENT_MANAGEMENT_PORT} > /dev/null"

# TODO: Use the existing Graph token contract instead of deploying a separate token for this.
# TODO: Add some CLI instructions to readme?
#   cd build/edgeandnode/subscription-payments
#   subscriptions="$(jq -r '.contract' contract/contract-deployment.json)"
#   token="$(jq -r '.token' contract/contract-deployment.json)"
#   cd cli
#   echo "${ACCOUNT_SECRET_KEY}" | cargo run -- \
#     "--subscriptions=${subscriptions}" "--token=${token}" \
#     subscribe --end="$(date -u '+%Y-%m-%dT%TZ' --date='10 min')" --rate=100000000000000

(cd build/edgeandnode/subscription-payments
  (cd contract && yarn build && yarn deploy-local)
  yq ".dataSources[0].source.address |= \"$(jq <contract/contract-deployment.json '.contract' -r)\"" \
    subgraph/subgraph.yaml -iy
  yq ".dataSources[0].network |= \"hardhat\"" \
    subgraph/subgraph.yaml -iy
  (cd subgraph && yarn && yarn create-local)
  deployment=$(cd subgraph && yarn deploy-local | grep "Build completed: " | awk '{print $3}' | sed -e 's/\x1b\[[0-9;]*m//g')
  echo "${deployment}"

  jq ".deployment |= \"${deployment}\"" contract/contract-deployment.json >../../subscriptions.json
  cat ../../subscriptions.json
  subscriptions="$(jq -r '.contract' contract/contract-deployment.json)"
  token="$(jq -r '.token' contract/contract-deployment.json)"

  (cd cli &&
    echo "${ACCOUNT_SECRET_KEY}" | cargo run -- \
      "--subscriptions=${subscriptions}" "--token=${token}" \
      subscribe --end="$(date -u '+%Y-%m-%dT%TZ' --date='10 min')" --rate=100000000000000)
)

./build/graphprotocol/indexer/packages/indexer-cli/bin/graph-indexer \
  indexer connect "http://localhost:${INDEXER_AGENT_MANAGEMENT_PORT}"
deployment="$(jq -r '.deployment' build/subscriptions.json)"
./build/graphprotocol/indexer/packages/indexer-cli/bin/graph-indexer \
  indexer rules prepare "${deployment}"

signal_ready subscriptions
