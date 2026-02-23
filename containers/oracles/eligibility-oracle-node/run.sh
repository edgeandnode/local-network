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

# Reset consumer group to the start of the topic. Stale committed offsets
# survive Redpanda restarts and can cause the oracle to skip new messages
# when the topic has been repopulated after a network restart.
rpk group seek eligibility-oracle --to start \
  --topics gateway_queries \
  --brokers="redpanda:${REDPANDA_KAFKA_PORT}" \
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
# Re-submit before the 300s eligibility period expires.
# Note that a new block needs to be mined to trigger the oracle node.
staleness_threshold_secs = 200

EOF

echo "=== Generated config.toml ===" >&2
cat config.toml >&2
echo "=============================" >&2

# Run in one-shot mode on a schedule, mirroring production (K8s CronJob).
# Each invocation rebuilds state from the compacted Kafka topic, evaluates
# eligibility, submits on-chain, then exits.
INTERVAL=10
CHAIN_RPC="http://chain:${CHAIN_RPC_PORT}"

# Forward SIGTERM/SIGINT to the running child so Docker stop is graceful.
child=0
trap 'kill -TERM "$child" 2>/dev/null; wait "$child"; exit 0' SIGTERM SIGINT

get_block_number() {
  curl -sf -X POST "$CHAIN_RPC" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    | jq -r '.result // empty' 2>/dev/null || true
}

echo "=== Running eligibility-oracle-node (one-shot, polling every ${INTERVAL}s) ==="
last_block=""
while true; do
  current_block=$(get_block_number)

  if [ -z "$current_block" ]; then
    echo "Could not fetch block number, retrying in ${INTERVAL}s"
    sleep "$INTERVAL" &
    child=$!
    wait "$child"
    continue
  fi

  if [ "$current_block" = "$last_block" ]; then
    sleep "$INTERVAL" &
    child=$!
    wait "$child"
    continue
  fi

  echo "--- New block: ${last_block:-none} -> ${current_block}, running oracle ---"
  eligibility-oracle --config config.toml &
  child=$!
  wait "$child" && echo "--- Oracle finished (ok) ---" \
                || echo "--- Oracle finished (exit $?) ---"
  last_block=$current_block

  sleep "$INTERVAL" &
  child=$!
  wait "$child"
done
