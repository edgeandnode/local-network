#!/bin/env sh
set -eu
. /opt/config/.env

. /opt/shared/lib.sh

## Parameters
# Pull the network subgraph deployment ID from the graph-node
network_subgraph_deployment=$(curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network" \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { deployment } }" }' \
  | jq -r '.data._meta.deployment')

tap_verifier=$(contract_addr TAPVerifier tap-contracts)

## Config
cat >config.json <<-EOF
{
  "dips": {
    "service": "0x1234567890abcdef1234567890abcdef12345678",
    "max_initial_amount": "1000000000000000000",
    "max_ongoing_amount_per_epoch": "500000000000000000",
    "max_epochs_per_collection": 10,
    "min_epochs_per_collection": 2,
    "duration_epochs": 20,
    "pricing_table": {
      "${CHAIN_ID}": {
        "base_price_per_epoch": "101",
        "price_per_entity": "1001"
      }
    }
  },
  "admin_rpc": {
    "listen_addr": "0.0.0.0:${DIPPER_ADMIN_RPC_PORT}",
    "gateway_operator_allowlist": [
      "${RECEIVER_ADDRESS}"
    ]
  },
  "indexer_rpc": {
    "listen_addr": "0.0.0.0:${DIPPER_INDEXER_RPC_PORT}",
    "allowlist": [
      "${RECEIVER_ADDRESS}"
    ]
  },
  "db": {
    "url": "postgres://postgres:${POSTGRES_PORT}/dipper_1",
    "username": "postgres",
    "password": "postgres",
    "max_connections": 10
  },
  "network": {
    "gateway_url": "http://gateway:${GATEWAY_PORT}",
    "api_key": "${GATEWAY_API_KEY}",
    "deployment_id": "${network_subgraph_deployment}",
    "update_interval": 60
  },
  "signer": {
    "secret_key": "${ACCOUNT0_SECRET}",
    "chain_id": 1337
  },
  "tap_signer": {
    "secret_key": "${ACCOUNT0_SECRET}",
    "chain_id": 1337,
    "verifier": "${tap_verifier}"
  },
  "iisa": {
    "endpoint": "http://iisa-mock:8080",
    "request_timeout": 30,
    "connect_timeout": 10,
    "max_retries": 3
  }
}
EOF

echo "=== Generated config.json ===" >&2
cat config.json >&2
echo "===========================" >&2

dipper-service ./config.json
