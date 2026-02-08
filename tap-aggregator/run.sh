#!/bin/sh
set -eu
. /opt/config/.env

. /opt/shared/lib.sh

tap_verifier=$(contract_addr TAPVerifier tap-contracts)
graph_tally_verifier=$(contract_addr GraphTallyCollector.address horizon)

export TAP_PORT="${TAP_AGGREGATOR}"
export TAP_PRIVATE_KEY="${ACCOUNT1_SECRET}"
export TAP_DOMAIN_CHAIN_ID=1337
export TAP_DOMAIN_VERIFYING_CONTRACT="${tap_verifier}"
export TAP_DOMAIN_VERIFYING_CONTRACT_V2="${graph_tally_verifier}"

tap_aggregator
