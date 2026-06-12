#!/usr/bin/env bash
# Inject a DIPs indexing-requirement signal into the dipper pipeline.
#
# Produces a plain-JSON message to the `indexing-requirements` Redpanda topic
# that dipper's signal consumer (consumer group dipper-local) reads. No signing
# — it's a trusted-producer topic. On receipt dipper runs IISA selection and
# submits a RecurringCollector.offer() on-chain; the indexing-payments subgraph
# then indexes the Offer / IndexingAgreement, which the DIPs-enabled
# indexer-agent accepts (and collects) on-chain.
#
# Message schema (dipper SignalMessage, serde_json):
#   { subgraph_deployment_id: String, redundancy_factor: u32,
#     chain_id: u64, version: u64 }
#
# Usage: dips-signal.sh <deployment-ipfs-hash> [redundancy_factor] [version]
set -euo pipefail

deployment=${1:?usage: dips-signal.sh <deployment-ipfs-hash> [redundancy_factor] [version]}
redundancy=${2:-1}
version=${3:-1}
chain_id=${CHAIN_ID:-1337}

msg=$(printf '{"subgraph_deployment_id":"%s","redundancy_factor":%s,"chain_id":%s,"version":%s}' \
  "$deployment" "$redundancy" "$chain_id" "$version")

# Ensure the topic exists (Redpanda auto-create is off; producing to a missing
# topic fails with UNKNOWN_TOPIC_OR_PARTITION). Idempotent.
docker exec redpanda rpk topic create indexing-requirements --brokers redpanda:9092 >/dev/null 2>&1 || true

echo "signal → indexing-requirements: $msg" >&2
printf '%s\n' "$msg" | docker exec -i redpanda rpk topic produce indexing-requirements --brokers redpanda:9092
