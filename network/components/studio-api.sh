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

export NODE_ENV=development

# Ensure there is a fresh local subgraph studio db
(dropdb $DB_NAME >/dev/null 2>&1) || true
(createdb $DB_NAME >/dev/null 2>&1) || true

cd $STUDIO_SOURCES

yarn
yarn setup

pushd packages/api

yarn start | tee /tmp/studio-api.log
