#!/bin/bash

export INDEXER_SERVICE_SOURCE_ROOT=$1
export INDEXER_AGENT_SOURCE_ROOT=$1
docker compose down
docker compose -f docker-compose.yaml \
-f overrides/indexer-service-ts-dev/indexer-service-ts-dev.yaml \
-f overrides/indexer-agent-dev/indexer-agent-dev.yaml \
up -d