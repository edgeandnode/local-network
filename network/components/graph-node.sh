#!/usr/bin/env bash

set -e

########################################################################
# Configuration

export DB_NAME=local_network_indexer_0_node
export POSTGRES_URL=postgresql://$POSTGRES_USERNAME:$POSTGRES_PASSWORD@localhost:5432/$DB_NAME
# export RUSTFLAGS='-L /Applications/Postgres.app/Contents/Versions/13/lib/'

export GRAPH_ETH_CALL_FULL_LOG=true
export GRAPH_EXPERIMENTAL_SUBGRAPH_VERSION_SWITCHING_MODE=synced
export GRAPH_ALLOW_NON_DETERMINISTIC_IPFS=true
export GRAPH_ALLOW_NON_DETERMINISTIC_FULLTEXT_SEARCH=true
export GRAPH_LOG_QUERY_TIMING=gql
export GRAPH_LOG=debug

########################################################################
# Run

# Ensure the local graph database exists and is fresh
(dropdb -h localhost -U $POSTGRES_USERNAME -w $DB_NAME >/dev/null 2>&1) || true
createdb -h localhost -U $POSTGRES_USERNAME -w $DB_NAME

cd $GRAPH_NODE_SOURCES

cargo watch -x \
    "run -p graph-node -- \
       --ethereum-rpc $ETHEREUM_NETWORK:$ETHEREUM \
       --ipfs http://127.0.0.1:5001 \
       --postgres-url $POSTGRES_URL" \
    | tee /tmp/graph-node.log

