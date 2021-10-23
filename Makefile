.PHONY: all
all: \
	docker-pull \
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

.PHONY: graphprotocol/contracts
graphprotocol/contracts:
	cd projects/$@ && yarn && yarn build && yalc publish

.PHONY: graphprotocol/common-ts
graphprotocol/common-ts: graphprotocol/contracts
	cd projects/$@/packages/common-ts && yalc add @graphprotocol/contracts
	cd projects/$@ && yarn
	cd projects/$@/packages/common-ts && yalc publish

.PHONY: graphprotocol/cost-model
graphprotocol/cost-model:
	cd projects/$@/node-plugin && yarn && yalc publish

.PHONY: graphprotocol/graph-network-subgraph
graphprotocol/graph-network-subgraph:
	cd projects/$@ && yarn

.PHONY: graphprotocol/graph-node
graphprotocol/graph-node:
	cd projects/$@ && cargo build -p graph-node

.PHONY: graphprotocol/indexer
graphprotocol/indexer: graphprotocol/common-ts graphprotocol/cost-model
	cd projects/$@/packages/indexer-agent && yalc add @graphprotocol/contracts
	cd projects/$@/packages/indexer-common && yalc add @graphprotocol/cost-model
	cd projects/$@/packages/indexer-agent && yalc add @graphprotocol/common-ts
	cd projects/$@/packages/indexer-cli && yalc add @graphprotocol/common-ts
	cd projects/$@/packages/indexer-common && yalc add @graphprotocol/common-ts
	cd projects/$@/packages/indexer-service && yalc add @graphprotocol/common-ts
	cd projects/$@ && yarn
