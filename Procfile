ipfs: ipfs daemon
postgres: bash scripts/run-postgres.bash 2>&1| tee /tmp/postgres.log
chain: bash scripts/run-chain.bash
contracts: sleep 10; bash scripts/setup-contracts.bash 2>&1| tee /tmp/contracts.log
graph-node: sleep 10; bash scripts/run-graph-node.bash
network-subgraph: sleep 80; bash scripts/setup-network-subgraph.bash 2>&1| tee /tmp/network-subgraph.log
studio-api: sleep 90; bash scripts/run-studio-api.bash
setup-client: sleep 120; bash scripts/setup-client.bash

indexer-agent: sleep 90; bash scripts/run-indexer-agent.bash
indexer-service: sleep 100; bash scripts/run-indexer-service.bash
setup-indexer: sleep 135; bash scripts/setup-indexer.bash

gateway: sleep 80; bash scripts/run-gateway.bash
gateway-agent: sleep 90; bash scripts/run-gateway-agent.bash
fisherman: sleep 90; bash scripts/run-fisherman.bash
# gateway-ts: sleep 100; bash scripts/run-gateway-ts.bash
