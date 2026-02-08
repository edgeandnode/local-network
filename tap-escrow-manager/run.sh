#!/bin/sh
set -eu
. /opt/config/.env

. /opt/shared/lib.sh

grt=$(contract_addr L2GraphToken.address horizon)
graph_tally_collector=$(contract_addr GraphTallyCollector.address horizon)
payments_escrow=$(contract_addr PaymentsEscrow.address horizon)

rpk topic create gateway_queries --brokers="redpanda:${REDPANDA_KAFKA_PORT}" || true
rpk topic create gateway_ravs --brokers="redpanda:${REDPANDA_KAFKA_PORT}" || true

cat >config.json <<-EOF
{
  "authorize_signers": true,
  "chain_id": 1337,
  "debts": {},
  "graph_tally_collector_contract": "${graph_tally_collector}",
  "payments_escrow_contract": "${payments_escrow}",
  "grt_allowance": 100,
  "grt_contract": "${grt}",
  "kafka": {
    "config": {
      "bootstrap.servers": "redpanda:${REDPANDA_KAFKA_PORT}"
    },
    "realtime_topic": "gateway_queries"
  },
  "network_subgraph": "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network",
  "query_auth": "freestuff",
  "rpc_url": "http://chain:${CHAIN_RPC_PORT}",
  "signers": ["${ACCOUNT1_SECRET}"],
  "secret_key": "${ACCOUNT0_SECRET}",
  "update_interval_seconds": 10
}
EOF
cat config.json

export RUST_LOG="info,tap_escrow_manager=debug"
tap-escrow-manager config.json
