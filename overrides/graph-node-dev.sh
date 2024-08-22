#!/bin/bash

COMPOSE_FILES=(
	-f docker-compose.yaml
	-f overrides/graph-node-dev/graph-node-dev.yaml
)
COMMAND=$1
shift
docker compose ${COMPOSE_FILES[@]} $COMMAND "$@"
