#!/bin/sh
set -eu
. /opt/.env

# Use GraphTallyCollector (V2) contract for Horizon mode
# This ensures the tap-aggregator uses the correct domain separator for V2 RAVs
v2_verifier="$(jq -r '."1337".GraphTallyCollector.address' /opt/horizon.json)"

export TAP_PORT="${TAP_AGGREGATOR}"
export TAP_PRIVATE_KEY="${ACCOUNT0_SECRET}"
export TAP_DOMAIN_CHAIN_ID=1337
export TAP_DOMAIN_NAME="TAP"
export TAP_DOMAIN_VERIFYING_CONTRACT="${v2_verifier}"
export TAP_DOMAIN_VERSION="2"

tap_aggregator
