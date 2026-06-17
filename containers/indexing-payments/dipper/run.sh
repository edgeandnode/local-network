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

subgraph_service=$(contract_addr SubgraphService.address subgraph-service)
recurring_collector=$(contract_addr RecurringCollector.address horizon)

signal_topic=$(kafka_topic indexing-requirements)

## Config
cat >config.json <<-EOF
{
  "dips": {
    "data_service": "${subgraph_service}",
    "recurring_collector": "${recurring_collector}",
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
      "${INDEXER_ADDRESS}"
    ]
  },
  "indexer_rpc": {
    "listen_addr": "0.0.0.0:${DIPPER_INDEXER_RPC_PORT}",
    "allowlist": [
      "${INDEXER_ADDRESS}"
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
    "secret_key": "${DEPLOYER_SECRET}",
    "chain_id": 1337
  },
  "chain_client": {
    "enabled": true,
    "providers": ["http://chain:${CHAIN_RPC_PORT}"],
    "subgraph_service_address": "${subgraph_service}",
    "indexing_payments_subgraph_url": "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/indexing-payments"
  },
  "iisa": {
    "endpoint": "http://iisa:8080",
    "request_timeout": 30,
    "connect_timeout": 10,
    "max_retries": 3
  },
  "signal": {
    "brokers": "redpanda:9092",
    "topic": "${signal_topic}",
    "consumer_group": "dipper-local"
  },
  "chain_listener": {
    "enabled": true,
    "subgraph_endpoint": "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/indexing-payments",
    "chain_id": ${CHAIN_ID},
    "poll_interval": 5,
    "request_timeout": 30,
    "max_retries": 3
  },
  "additional_networks": {
    "1337": "hardhat"
  }
}
EOF

echo "=== Generated config.json ===" >&2
cat config.json >&2
echo "===========================" >&2

dipper-service ./config.json
