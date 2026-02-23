#!/bin/env sh
set -eu
. /opt/config/.env

. /opt/shared/lib.sh

## Parameters
echo "Waiting for network subgraph..." >&2
network_subgraph_deployment=$(wait_for_gql \
  "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network" \
  "{ _meta { deployment } }" \
  ".data._meta.deployment")

tap_verifier=$(contract_addr TAPVerifier tap-contracts)
subgraph_service=$(contract_addr SubgraphService.address subgraph-service)

## Config
cat >config.json <<-EOF
{
  "dips": {
    "data_service": "${subgraph_service}",
    "recurring_collector": "0x0000000000000000000000000000000000000000",
    "max_initial_tokens": "1000000000000000000",
    "max_ongoing_tokens_per_second": "1000000000000000",
    "max_seconds_per_collection": 86400,
    "min_seconds_per_collection": 3600,
    "duration_seconds": null,
    "deadline_seconds": 300,
    "pricing_table": {
      "${CHAIN_ID}": {
        "tokens_per_second": "101",
        "tokens_per_entity_per_second": "1001"
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
    "endpoint": "http://iisa:8080",
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
