#!/bin/sh
set -eu
. /opt/.env

cd /opt
tap_verifier=$(jq -r '."1337".TAPVerifier.address' /opt/contracts.json)
cat >config.json <<-EOF
{
  "attestations": {
    "chain_id": "1337",
    "dispute_manager": "$(jq -r '."1337".DisputeManager.address' /opt/contracts.json)"
  },
  "api_keys": [
    {
      "key": "deadbeefdeadbeefdeadbeefdeadbeef",
      "user_address": "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
      "query_status": "ACTIVE"
    }
  ],
  "exchange_rate_provider": 1.0,
  "graph_env_id": "local",
  "indexer_selection_retry_limit": 2,
  "ip_rate_limit": 100,
  "kafka": {
    "bootstrap.servers": "redpanda:${REDPANDA_KAFKA}"
  },
  "log_json": false,
  "min_graph_node_version": "0.0.0",
  "min_indexer_version": "0.0.0",
  "network_subgraph": "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network",
  "payment_required": true,
  "port_api": 7700,
  "port_metrics": 7301,
  "query_fees_target": 40e-6,
  "scalar": {
    "chain_id": "1337",
    "signer": "${ACCOUNT0_SECRET}",
    "verifier": "${tap_verifier}"
  }
}
EOF
cat config.json
export RUST_LOG=info,gateway_framework=trace,graph_gateway=trace
graph-gateway ./config.json
