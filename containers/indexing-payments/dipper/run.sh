#!/usr/bin/env sh
set -eu
# shellcheck source=/dev/null
. /opt/config/.env

# shellcheck source=/dev/null
. /opt/shared/lib.sh

# --- Start cargo build immediately (no deps needed) ---
WORK_DIR="$(pwd)"
if [ -d /opt/source ] && [ -f /opt/source/Cargo.toml ]; then
  cd /opt/source
  cargo build --bin dipper-service --release &
  BUILD_PID=$!
  BUILD_FROM_SOURCE=true
  cd "$WORK_DIR"
else
  BUILD_FROM_SOURCE=false
fi

# --- Wait for dependencies in parallel with build ---
wait_for_config

# Wait for network subgraph to be deployed and queryable
echo "Waiting for network subgraph..." >&2
network_subgraph_deployment=$(wait_for_gql \
  "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/graph-network" \
  "{ _meta { deployment } }" \
  ".data._meta.deployment" \
  600)

subgraph_service=$(contract_addr SubgraphService.address subgraph-service)
recurring_collector=$(contract_addr RecurringCollector.address horizon)
recurring_agreement_manager=$(contract_addr RecurringAgreementManager.address issuance)

# Config for dipper-service. chain_client derives chain_id, the collector and the
# SubgraphService address from the signer/dips sections (edgeandnode/dipper#626, #643).
cat >config.json <<-EOF
{
  "dips": {
    "data_service": "${subgraph_service}",
    "recurring_collector": "${recurring_collector}",
    "recurring_agreement_manager": "${recurring_agreement_manager}",
    "max_agreement_grt_per_30_days": 20000,
    "max_seconds_per_collection": 86400,
    "min_seconds_per_collection": 3600,
    "duration_seconds": null,
    "deadline_seconds": 600,
    "pricing_table": {
      "${CHAIN_ID}": {
        "tokens_per_second": "174000000000000",
        "tokens_per_entity_per_second": "78000"
      }
    }
  },
  "admin_rpc": {
    "listen_addr": "0.0.0.0:${DIPPER_ADMIN_RPC_PORT}",
    "gateway_operator_allowlist": [
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
    "chain_id": ${CHAIN_ID}
  },
  "chain_client": {
    "enabled": true,
    "providers": ["http://chain:${CHAIN_RPC_PORT}"],
    "request_timeout": 30,
    "max_retries": 3,
    "gas_price_multiplier": 1.2,
    "max_gas_price_gwei": 100,
    "gas_buffer_multiplier": 2.0,
    "gas_floor": 100000,
    "gas_max_addition": 200000
  },
  "iisa": {
    "endpoint": "http://iisa:8080",
    "request_timeout": 30,
    "connect_timeout": 10,
    "max_retries": 3
  },
  "expiration": {
    "enabled": true,
    "interval": 10,
    "batch_size": 100
  },
  "chain_listener": {
    "enabled": true,
    "subgraph_endpoint": "http://graph-node:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/name/indexing-payments",
    "poll_interval": 5,
    "chain_id": ${CHAIN_ID},
    "bypass_chain_clock_defenses": true
  },
  "additional_networks": {
    "${CHAIN_ID}": "${CHAIN_NAME}"
  }
}
EOF

echo "=== Generated config.json ===" >&2
cat config.json >&2
echo "===========================" >&2

# --- Wait for build to finish ---
if [ "$BUILD_FROM_SOURCE" = "true" ]; then
  echo "Waiting for cargo build to complete..."
  wait "$BUILD_PID"
  echo "Build complete"

  # Wait for runtime deps (gateway, iisa must be reachable before dipper starts)
  wait_for_url "http://gateway:${GATEWAY_PORT}" 600
  wait_for_url "http://iisa:8080/health" 600

  exec /opt/source/target/release/dipper-service "${WORK_DIR}/config.json"
else
  exec dipper-service "${WORK_DIR}/config.json"
fi
