#!/bin/bash

# This script queries the indexer service through the gatewey


# Mine some blocks to prevent gateway "too far behind" error
./scripts/mine-block.sh 10 > /dev/null 2>&1

# Number of times to run the commands, default is 1
count=${1:-1}

for ((i=0; i<count; i++))
do
    curl "http://localhost:7700/api/subgraphs/id/BFr2mx7FgkJ36Y6pE5BiXs1KmNUmVDCnL82KUSdcLW1g" \
        -H 'content-type: application/json' \
        -H "Authorization: Bearer deadbeefdeadbeefdeadbeefdeadbeef" \
        -d '{"query": "{ _meta { block { number } } }"}'
    echo
done
