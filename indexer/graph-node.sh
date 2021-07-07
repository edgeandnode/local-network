#!/usr/bin/env bash

set -e

########################################################################
# Configuration

export GRAPH_NODE_SOURCES=/path/to/graph-node
export POSTGRES_URL=postgresql://someuser:somepass@localhost:5432/graph

########################################################################
# Run

cd $GRAPH_NODE_SOURCES

export GRAPH_ALLOW_NON_DETERMINISTIC_IPFS=true
export GRAPH_ALLOW_NON_DETERMINISTIC_FULLTEXT_SEARCH=true
export GRAPH_LOG=trace

cargo watch -x \
    "run -p graph-node -- \
       --ethereum-rpc mainnet:https://eth-mainnet.alchemyapi.io/v2/iemhQFg2k89zAO1-gSngWqkLHTZ-Byc_ \
                      rinkeby:https://eth-rinkeby.alchemyapi.io/v2/MbPzjkEmyF891zBE51Q1c5M4IQAEXZ-9 \
       --ipfs https://ipfs.network.thegraph.com/ \
       --postgres-url $GRAPH_NODE_POSTGRES_URL" \
    | tee /tmp/graph-node.log
