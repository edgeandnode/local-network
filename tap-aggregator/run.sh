#!/bin/sh
set -eu
. /opt/.env

tap_verifier="$(jq -r '."1337".TAPVerifier' /opt/tap-contracts.json)"
graph_tally_verifier="$(jq -r '."1337".GraphTallyCollector.address' /opt/horizon.json)"

export TAP_PORT="${TAP_AGGREGATOR}"
export TAP_PRIVATE_KEY="${ACCOUNT0_SECRET}"
export TAP_DOMAIN_CHAIN_ID=1337
export TAP_DOMAIN_VERIFYING_CONTRACT="${tap_verifier}"
export TAP_DOMAIN_VERIFYING_CONTRACT_V2="${graph_tally_verifier}"

tap_aggregator
