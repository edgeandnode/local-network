#!/bin/sh
set -eu
. /opt/.env

grt="$(jq -r '."1337".L2GraphToken.address' /opt/horizon.json)"
graph_tally_collector="$(jq -r '."1337".GraphTallyCollector.address' /opt/horizon.json)"
payments_escrow="$(jq -r '."1337".PaymentsEscrow.address' /opt/horizon.json)"

# Generate signer private key from a test mnemonic
SIGNER_MNEMONIC="test test test test test test test test test test test waste"
SIGNER_SECRET="$(cast wallet private-key --mnemonic "${SIGNER_MNEMONIC}" --mnemonic-index 0)"

rpk topic create gateway_queries --brokers="redpanda:${REDPANDA_KAFKA}" || true
rpk topic create gateway_ravs --brokers="redpanda:${REDPANDA_KAFKA}" || true

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
      "bootstrap.servers": "redpanda:${REDPANDA_KAFKA}"
    },
    "realtime_topic": "gateway_queries"
  },
  "network_subgraph": "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network",
  "query_auth": "freestuff",
  "rpc_url": "http://chain:${CHAIN_RPC}",
  "signers": ["${SIGNER_SECRET}"],
  "secret_key": "${ACCOUNT0_SECRET}",
  "update_interval_seconds": 10
}
EOF
cat config.json

export RUST_LOG="info,tap_escrow_manager=debug"
tap-escrow-manager config.json
