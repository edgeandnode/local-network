#!/usr/bin/env bash

set -e

########################################################################
# Configuration

export INDEXER_CLI_SOURCES=$INDEXER_SOURCES/packages/indexer-cli/

########################################################################
# Run

cd $INDEXER_CLI_SOURCES

yarn

# Connect to indexer management API server
./bin/graph-indexer indexer connect http://localhost:18000

# Create rule to index network subgraph
./bin/graph-indexer indexer rules set QmcUrDscqmmf3FAHNyGW8kJM6ZBp62mgFrJNFJFPkPzNEy decisionBasis always allocationAmount 500000

# Create global rule to index subgraphs with signal > 500
./bin/graph-indexer indexer rules set global decisionBasis rules minSignal 500 allocationAmount 500000

