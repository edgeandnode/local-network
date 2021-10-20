.PHONY: all
all: \
	docker-pull \
	graphprotocol/contracts \
	graphprotocol/common-ts

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
	cd projects/$@ && yarn
