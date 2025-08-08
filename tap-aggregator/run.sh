#!/bin/sh
set -eu
. /opt/.env

graph_tally_verifier="$(jq -r '."1337".GraphTallyCollector.address' /opt/horizon.json)"

export TAP_PORT="${TAP_AGGREGATOR}"
export TAP_PRIVATE_KEY="${ACCOUNT0_SECRET}"
export TAP_DOMAIN_CHAIN_ID=1337
export TAP_DOMAIN_NAME="GraphTallyCollector"
export TAP_DOMAIN_VERIFYING_CONTRACT="${graph_tally_verifier}"
export TAP_DOMAIN_VERSION="1"

tap_aggregator
