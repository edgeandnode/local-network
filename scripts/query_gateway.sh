#!/bin/bash

# This script queries the indexer service through the gatewey

# Mine some blocks to prevent gateway "too far behind" error
./scripts/mine-block.sh 10 > /dev/null 2>&1

GATEWAY_HOST="${GATEWAY_HOST:-localhost}"
GATEWAY_PORT="${GATEWAY_PORT:-7700}"

# Number of times to run the commands, default is 1
count=${1:-1}
deployment_id=${2:-"BFr2mx7FgkJ36Y6pE5BiXs1KmNUmVDCnL82KUSdcLW1g"}

for ((i=0; i<count; i++))
do
    curl "http://${GATEWAY_HOST}:${GATEWAY_PORT}/api/subgraphs/id/${deployment_id}" \
        -H 'content-type: application/json' \
        -H "Authorization: Bearer deadbeefdeadbeefdeadbeefdeadbeef" \
        -d '{"query": "{ _meta { block { number } } }"}'
    echo
done
