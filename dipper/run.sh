
#!/bin/sh
set -eu
. /opt/.env

cd /opt
network_subgraph_deployment=$(curl -s "http://graph-node:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network" \
  -H 'content-type: application/json' \
  -d '{"query": "{ _meta { deployment } }" }' \
  | jq -r '.data._meta.deployment')
tap_verifier=$(jq -r '."1337".TAPVerifier.address' /opt/contracts.json)
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
      "1337": {
        "base_price_per_epoch": "0x100",
        "price_per_entity": "0x100"
      }
    }
  },
  "admin_rpc": {
    "listen_addr": "127.0.0.1:${DIPPER_ADMIN_RPC_PORT}",
    "allowlist": [
        "${RECEIVER_ADDRESS}"
    ]
  },
  "indexer_rpc": {
    "listen_addr": "127.0.0.1:${DIPPER_INDEXER_RPC_PORT}",
    "allowlist": [
        "${RECEIVER_ADDRESS}"
    ]
  },
  "db": {
    "url": "postgres://localhost:5432/dipper",
    "username": "postgres",
    "password": "postgres",
    "max_connections": 10
  },
  "network": {
    "gateway_url": "http://127.0.0.1:${POSTGRES}",
    "api_key": "deadbeefdeadbeefdeadbeefdeadbeef",
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
  }
}
EOF
cat config.json
export RUST_LOG=debug
dipper ./config.json
