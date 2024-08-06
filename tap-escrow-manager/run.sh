#!/bin/sh
set -eu
. /opt/.env

grt="$(jq -r '."1337".GraphToken.address' /opt/contracts.json)"
tap_escrow="$(jq -r '."1337".TAPEscrow.address' /opt/contracts.json)"

cast send "--rpc-url=http://chain:${CHAIN_RPC}" "--mnemonic=${MNEMONIC}" \
  "${grt}" 'approve(address,uint256)' "${tap_escrow}" 1000000000000000000000000

rpk topic create gateway_indexer_attempts --brokers="redpanda:${REDPANDA_KAFKA}" || true

cat >config.json <<-EOF
{
  "chain_id": 1337,
  "debts": {},
  "escrow_contract": "${tap_escrow}",
  "escrow_subgraph": "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/semiotic/tap",
  "graph_env": "local",
  "grt_allowance": 1000,
  "grt_contract": "0x3Aa5ebB10DC797CAC828524e59A333d0A371443c",
  "kafka": {
    "cache": "/opt/cache.json",
    "config": {
      "bootstrap.servers": "redpanda:${REDPANDA_KAFKA}"
    },
    "topic": "gateway_indexer_attempts"
  },
  "network_subgraph": "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network",
  "query_auth": "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
  "rpc_url": "http://chain:${CHAIN_RPC}",
  "signers": ["${ACCOUNT0_SECRET}"],
  "secret_key": "${ACCOUNT0_SECRET}",
  "update_interval_seconds": 10
}
EOF
cat config.json

touch /opt/cache.json
export RUST_LOG="info,tap_escrow_manager=debug"
tap-escrow-manager config.json
