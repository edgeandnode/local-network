#!/bin/bash
set -eu
. /opt/config/.env
. /opt/shared/lib.sh

# Wait for the REO contract address to be available in issuance.json
reo_address=""
for f in issuance.json; do
  reo_address=$(jq -r '.["1337"].RewardsEligibilityOracle.address // empty' "/opt/config/$f" 2>/dev/null || true)
  [ -n "$reo_address" ] && break
done

if [ -z "$reo_address" ]; then
  echo "ERROR: RewardsEligibilityOracle address not found in issuance.json"
  echo "The REO contract must be deployed before starting the oracle node."
  exit 1
fi

echo "=== Configuring eligibility-oracle-node ==="
echo "  REO contract: ${reo_address}"
echo "  Chain ID: ${CHAIN_ID}"
echo "  Redpanda: redpanda:${REDPANDA_KAFKA_PORT}"

# Create compacted output topic (idempotent)
rpk topic create indexer_daily_metrics \
  --brokers="redpanda:${REDPANDA_KAFKA_PORT}" \
  -c cleanup.policy=compact,delete \
  -c retention.ms=7776000000 \
  2>/dev/null || true

# Generate config.toml with local network values
cat >config.toml <<EOF
[kafka]
bootstrap_servers = "redpanda:${REDPANDA_KAFKA_PORT}"
# Shorter rebuild timeout for local network
rebuild_timeout_secs = 10

[eligibility]
# Relaxed thresholds for local testing
analysis_period_days = 1
min_online_days = 1
min_subgraphs = 1
max_latency_ms = 10000
max_blocks_behind = 100000

[blockchain]
contract_address = "${reo_address}"
rpc_urls = ["http://chain:${CHAIN_RPC_PORT}"]
chain_id = ${CHAIN_ID}
private_key = "\$BLOCKCHAIN_PRIVATE_KEY"
# Submit all eligible indexers regardless of staleness in local network
staleness_threshold_hours = 0

[scheduling]
# Run every 60 seconds in local network (production: 3 hours)
interval_secs = 60
EOF

echo "=== Generated config.toml ===" >&2
cat config.toml >&2
echo "=============================" >&2

echo "=== Starting eligibility-oracle-node (daemon mode) ==="
exec eligibility-oracle --config config.toml --daemon
