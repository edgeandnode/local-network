.PHONY: all
all: \
	docker-pull \
	edgeandnode/gateway \
	edgeandnode/graph-gateway \
	edgeandnode/indexer-selection \
	edgeandnode/network-services \
	edgeandnode/subgraph-studio \
	graphprotocol/agora \
	graphprotocol/contracts \
	graphprotocol/common-ts \
	graphprotocol/graph-network-subgraph \
	graphprotocol/graph-node \
	graphprotocol/indexer

.PHONY: clean
clean:
	find . -name node_modules -type d -prune -exec rm -rf '{}' +
	rm -rf projects/graphprotocol/contracts/{build,cache}
	rm -rf projects/graphprotocol/common-ts/packages/common-ts/dist

.PHONY: docker-pull
docker-pull:
	docker pull timescale/timescaledb:latest-pg12

.PHONY: edgeandnode/gateway
edgeandnode/gateway: edgeandnode/indexer-selection graphprotocol/common-ts
	cd projects/$@/packages/gateway \
		&& yalc link @graphprotocol/common-ts \
		&& yalc update
	cd projects/$@/packages/query-engine \
		&& yalc link @edgeandnode/indexer-selection \
		&& yalc link @graphprotocol/common-ts \
		&& yalc link @graphprotocol/contracts \
		&& yalc update
	cd projects/$@ \
		&& yalc link @graphprotocol/common-ts \
		&& yalc update \
		&& yarn

.PHONY: edgeandnode/graph-gateway
edgeandnode/graph-gateway:
	cd projects/$@ && cargo build

.PHONY: edgeandnode/indexer-selection
edgeandnode/indexer-selection:
	cd projects/$@ && yarn && yalc push

.PHONY: edgeandnode/network-services
edgeandnode/network-services:
	cd projects/$@ && cargo build

.PHONY: edgeandnode/subgraph-studio
edgeandnode/subgraph-studio:
	cd projects/$@ && yarn

.PHONY: graphprotocol/contracts
graphprotocol/contracts:
	cd projects/$@ && yarn && yarn build && yalc push

.PHONY: graphprotocol/common-ts
graphprotocol/common-ts: graphprotocol/contracts
	cd projects/$@/packages/common-ts \
		&& yalc link @graphprotocol/contracts \
		&& yalc update
	cd projects/$@ \
		&& yalc link @graphprotocol/contracts \
		&& yalc update \
		&& yarn
	cd projects/$@/packages/common-ts \
		&& yalc push

.PHONY: graphprotocol/agora
graphprotocol/agora:
	cd projects/$@/node-plugin && yarn && yalc push

.PHONY: graphprotocol/graph-network-subgraph
graphprotocol/graph-network-subgraph: graphprotocol/common-ts
	cd projects/$@ \
		&& yalc link @graphprotocol/common-ts \
		&& yalc link @graphprotocol/contracts \
		&& yalc update \
		&& yarn

.PHONY: graphprotocol/graph-node
graphprotocol/graph-node:
	cd projects/$@ && cargo build -p graph-node

.PHONY: graphprotocol/indexer
graphprotocol/indexer: graphprotocol/common-ts graphprotocol/agora
	cd projects/$@/packages/indexer-agent \
		&& yalc link @graphprotocol/common-ts \
		&& yalc link @graphprotocol/contracts \
		&& yalc update
	cd projects/$@/packages/indexer-common \
		&& yalc link @graphprotocol/common-ts \
		&& yalc link @graphprotocol/cost-model \
		&& yalc update
	cd projects/$@/packages/indexer-cli \
		&& yalc link @graphprotocol/common-ts \
		&& yalc update
	cd projects/$@/packages/indexer-service \
		&& yalc link @graphprotocol/common-ts \
		&& yalc update
	cd projects/$@ && yarn
