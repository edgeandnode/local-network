#!/bin/sh
set -eu
. /opt/.env

cd /opt
graph_tally_verifier=$(jq -r '."1337".GraphTallyCollector.address' /opt/horizon.json)
dispute_manager=$(jq -r '."1337".DisputeManager.address' /opt/subgraph-service.json)
subgraph_service=$(jq -r '."1337".SubgraphService.address' /opt/subgraph-service.json)
network_subgraph_deployment=$(curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network" \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { deployment } }" }' \
  | jq -r '.data._meta.deployment')
cat >config.json <<-EOF
{
  "attestations": {
    "chain_id": "1337",
    "dispute_manager": "${dispute_manager}"
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
    "verifier": "${graph_tally_verifier}"
  },
  "subgraph_service": "${subgraph_service}"
}
EOF
cat config.json
export RUST_LOG=info,gateway_framework=trace,graph_gateway=trace
graph-gateway ./config.json
