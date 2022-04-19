#!/bin/sh
. ./prelude.sh

await "curl -sf localhost:${INDEXER_AGENT_MANAGEMENT_PORT} > /dev/null"

cd build/graphprotocol/indexer/packages/indexer-cli

# Connect to indexer management API server
./bin/graph-indexer indexer connect "http://localhost:${INDEXER_AGENT_MANAGEMENT_PORT}"
# Create rule to index network subgraph
./bin/graph-indexer indexer rules set "${NETWORK_SUBGRAPH_DEPLOYMENT}" \
  decisionBasis always \
  allocationAmount 500000
# Create global rule to index subgraphs with signal > 500
./bin/graph-indexer indexer rules set global \
  decisionBasis rules minSignal 500 \
  allocationAmount 500000
