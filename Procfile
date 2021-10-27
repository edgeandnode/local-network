ipfs: ipfs daemon
postgres: bash scripts/run-postgres.bash
chain: bash scripts/run-chain.bash
contracts: sleep 5; bash scripts/run-contracts.bash |& tee /tmp/contracts.log
graph-node: sleep 5; bash scripts/run-graph-node.bash
network-subgraph: sleep 80; bash scripts/setup-network-subgraph.bash
studio-api: sleep 90; bash scripts/run-studio-api.bash
setup-client: sleep 110; bash scripts/setup-client.bash

indexer-agent: sleep 90; bash scripts/run-indexer-agent.bash
indexer-service: sleep 100; bash scripts/run-indexer-service.bash
setup-indexer: sleep 135; bash scripts/setup-indexer.bash

gateway-agent: sleep 90; bash scripts/run-gateway-agent.bash
gateway: sleep 100; bash scripts/run-gateway.bash
