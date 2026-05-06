#!/bin/sh
set -eu
. /opt/config/.env

. /opt/shared/lib.sh

graph_tally_verifier=$(contract_addr GraphTallyCollector.address horizon)

export GRAPH_TALLY_PORT="${GRAPH_TALLY_AGGREGATOR_PORT}"
export GRAPH_TALLY_PRIVATE_KEY="${ACCOUNT1_SECRET}"
export GRAPH_TALLY_DOMAIN_CHAIN_ID=1337
export GRAPH_TALLY_DOMAIN_VERIFYING_CONTRACT="${graph_tally_verifier}"

graph_tally_aggregator
