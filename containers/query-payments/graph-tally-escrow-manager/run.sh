#!/bin/sh
set -eu
. /opt/config/.env

. /opt/shared/lib.sh

grt=$(contract_addr L2GraphToken.address horizon)
graph_tally_collector=$(contract_addr GraphTallyCollector.address horizon)
payments_escrow=$(contract_addr PaymentsEscrow.address horizon)

queries_topic=$(kafka_topic gateway_queries)
rpk topic create "$queries_topic" --brokers="redpanda:9092" || true
ravs_topic=$(kafka_topic gateway_ravs)
rpk topic create "$ravs_topic" --brokers="redpanda:9092" || true

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
      "bootstrap.servers": "redpanda:9092"
    },
    "realtime_topic": "${queries_topic}"
  },
  "network_subgraph": "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network",
  "query_auth": "freestuff",
  "rpc_url": "http://chain:${CHAIN_RPC_PORT}",
  "signers": ["${GOVERNOR_SECRET}"],
  "secret_key": "${DEPLOYER_SECRET}",
  "update_interval_seconds": 10
}
EOF
cat config.json

export RUST_LOG="info,graph_tally_escrow_manager=debug"
graph_tally_escrow_manager config.json
