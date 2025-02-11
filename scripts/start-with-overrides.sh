#!/bin/bash
export INDEXER_AGENT_SOURCE_ROOT=$HOME/Development/en/indexer
docker compose -f docker-compose.yaml \
-f overrides/indexer-agent-dev/indexer-agent-dev.yaml up -d $@
