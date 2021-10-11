#!/usr/bin/env bash

set -e

########################################################################
# Configuration

export STUDIO_SOURCES=~/thegraph/workspaces/subgraph-studio/
export DB_HOST=localhost
export DB_NAME=local_network_subgraph_studio
export DB_USER=$POSTGRES_USERNAME
export DB_PASS=$POSTGRES_PASSWORD

########################################################################
# Run

cd $STUDIO_SOURCES

yarn

# Create test users
# 2 users
# 1 user has an API key
yarn knex seed:run --specific test-users.ts

# Activate queries
(psql -U "$POSTGRES_USERNAME" -d $DB_NAME -c 'update "Users" set "queriesActivated" = true;' >/dev/null 2>&1) || true
