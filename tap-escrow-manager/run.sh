#!/bin/sh
set -eu
. /opt/.env

grt="$(jq -r '."1337".L2GraphToken.address' /opt/horizon.json)"
tap_escrow="$(jq -r '."1337".TAPEscrow.address' /opt/tap-contracts.json)"

rpk topic create gateway_queries --brokers="redpanda:${REDPANDA_KAFKA}" || true

cat >config.json <<-EOF
{
  "authorize_signers": true,
  "chain_id": 1337,
  "debts": {},
  "escrow_contract": "${tap_escrow}",
  "escrow_subgraph": "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/semiotic/tap",
  "grt_allowance": 100,
  "grt_contract": "${grt}",
  "kafka": {
    "config": {
      "bootstrap.servers": "redpanda:${REDPANDA_KAFKA}"
    },
    "realtime_topic": "gateway_queries"
  },
  "network_subgraph": "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network",
  "query_auth": "freestuff",
  "rpc_url": "http://chain:${CHAIN_RPC}",
  "signers": ["${ACCOUNT0_SECRET}"],
  "secret_key": "${ACCOUNT0_SECRET}",
  "update_interval_seconds": 10
}
EOF
cat config.json

export RUST_LOG="info,tap_escrow_manager=debug"
tap-escrow-manager config.json
