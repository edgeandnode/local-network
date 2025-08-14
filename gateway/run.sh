#!/bin/sh
set -eu

# Source the environment variables from .env file
. /opt/.env

cd /opt
# V2: Use GraphTallyCollector for V2 receipts instead of V1 TAPVerifier
graph_tally_collector=$(jq -r '."1337".GraphTallyCollector.address' /opt/horizon.json)
network_subgraph_deployment=$(curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network" \
  -H 'content-type: application/json' \
  -d '{"query": "{ subgraphs(first: 1) { versions(first: 1) { subgraphDeployment { ipfsHash } } } }" }' \
  | jq -r '.data.subgraphs[0].versions[0].subgraphDeployment.ipfsHash')
cat >config.json <<-EOF
{
  "attestations": {
    "chain_id": "1337",
    "dispute_manager": "$(jq -r '."1337".DisputeManager.address' /opt/subgraph-service.json)"
  },
  "api_keys": [
    {
      "key": "${GATEWAY_API_KEY}",
      "user_address": "${ACCOUNT0_ADDRESS}",
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
  "network_subgraph": {
    "url": "http://indexer-service:${INDEXER_SERVICE}/subgraphs/id/Qmc2CbqucMvaS4GFvt2QUZWvRwSZ3K5ipeGvbC6UUBf616"
  },
  "trusted_indexers": [
    {
      "url": "http://indexer-service:${INDEXER_SERVICE}/subgraphs/id/Qmc2CbqucMvaS4GFvt2QUZWvRwSZ3K5ipeGvbC6UUBf616",
      "auth": "freestuff"
    }
  ],
  "payment_required": true,
  "port_api": 7700,
  "port_metrics": 7301,
  "query_fees_target": 40e-6,
  "receipts": {
    "chain_id": "1337",
    "signer": "${ACCOUNT0_SECRET}",
    "verifier": "${graph_tally_collector}"
  }
}
EOF
cat config.json
export RUST_LOG=info,gateway_framework=trace,graph_gateway=trace
graph-gateway ./config.json
