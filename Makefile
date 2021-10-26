.PHONY: all
all: \
	docker-pull \
	edgeandnode/gateway \
	edgeandnode/indexer-selection \
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
		&& yalc add @graphprotocol/common-ts
	cd projects/$@/packages/query-engine \
		&& yalc add @edgeandnode/indexer-selection \
		&& yalc add @graphprotocol/common-ts
	cd projects/$@ \
		&& yalc add @graphprotocol/common-ts \
		&& yarn

.PHONY: edgeandnode/indexer-selection
edgeandnode/indexer-selection:
	cd projects/$@ && yarn && yalc publish --push

.PHONY: graphprotocol/contracts
graphprotocol/contracts:
	cd projects/$@ && yarn && yarn build && yalc publish --push

.PHONY: graphprotocol/common-ts
graphprotocol/common-ts: graphprotocol/contracts
	cd projects/$@/packages/common-ts && yalc add @graphprotocol/contracts
	cd projects/$@ && yarn
	cd projects/$@/packages/common-ts && yalc publish --push

.PHONY: graphprotocol/cost-model
graphprotocol/cost-model:
	cd projects/$@/node-plugin && yarn && yalc publish --push

.PHONY: graphprotocol/graph-network-subgraph
graphprotocol/graph-network-subgraph:
	cd projects/$@ && yarn

.PHONY: graphprotocol/graph-node
graphprotocol/graph-node:
	cd projects/$@ && cargo build -p graph-node

.PHONY: graphprotocol/indexer
graphprotocol/indexer: graphprotocol/common-ts graphprotocol/cost-model
	cd projects/$@/packages/indexer-agent \
		&& yalc add @graphprotocol/common-ts \
		&& yalc add @graphprotocol/contracts
	cd projects/$@/packages/indexer-common \
		&& yalc add @graphprotocol/common-ts \
		&& yalc add @graphprotocol/cost-model
	cd projects/$@/packages/indexer-cli \
		&& yalc add @graphprotocol/common-ts
	cd projects/$@/packages/indexer-service \
		&& yalc add @graphprotocol/common-ts
	cd projects/$@ && yarn
