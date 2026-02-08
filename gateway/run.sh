#!/bin/sh
set -eu
. /opt/config/.env

. /opt/shared/lib.sh

cd /opt
graph_tally_verifier=$(contract_addr GraphTallyCollector.address horizon)
tap_verifier=$(contract_addr TAPVerifier tap-contracts)
dispute_manager=$(contract_addr DisputeManager.address subgraph-service)
legacy_dispute_manager=$(contract_addr LegacyDisputeManager.address subgraph-service)
subgraph_service=$(contract_addr SubgraphService.address subgraph-service)
network_subgraph_deployment=$(curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network" \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { deployment } }" }' \
  | jq -r '.data._meta.deployment')
cat >config.json <<-EOF
{
  "attestations": {
    "chain_id": "1337",
    "dispute_manager": "${dispute_manager}",
    "legacy_dispute_manager": "${legacy_dispute_manager}"
  },
  "api_keys": [
    {
      "key": "${GATEWAY_API_KEY}",
      "user_address": "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
      "query_status": "ACTIVE"
    }
  ],
  "exchange_rate_provider": 1.0,
  "graph_env_id": "local",
  "indexer_selection_retry_limit": 2,
  "kafka": {
    "bootstrap.servers": "redpanda:${REDPANDA_KAFKA}"
  },
  "log_json": false,
  "min_graph_node_version": "0.0.0",
  "min_indexer_version": "0.0.0",
  "trusted_indexers": [
    {
      "url": "http://indexer-service:${INDEXER_SERVICE}/subgraphs/id/${network_subgraph_deployment}",
      "auth": "freestuff"
    }
  ],
  "payment_required": true,
  "port_api": 7700,
  "port_metrics": 7301,
  "query_fees_target": 40e-6,
  "receipts": {
    "chain_id": "1337",
    "payer": "${ACCOUNT0_ADDRESS}",
    "signer": "${ACCOUNT1_SECRET}",
    "verifier": "${graph_tally_verifier}",
    "legacy_verifier": "${tap_verifier}"
  },
  "subgraph_service": "${subgraph_service}"
}
EOF
cat config.json
export RUST_LOG=info,gateway_framework=trace,graph_gateway=trace
graph-gateway ./config.json
