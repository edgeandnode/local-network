#!/usr/bin/env bash

set -e

########################################################################
# Configuration

export STUDIO_SOURCES=~/src/edgeandnode/subgraph-studio

export DB_HOST=localhost
export DB_NAME=local_network_subgraph_studio
export DB_USER=$POSTGRES_USERNAME
export DB_PASS=$POSTGRES_PASSWORD

########################################################################
# Run

export NODE_ENV=development

# Ensure there is a fresh local subgraph studio db
(dropdb -h localhost -U $POSTGRES_USERNAME -w $DB_NAME >/dev/null 2>&1) || true
createdb -h localhost -U $POSTGRES_USERNAME -w $DB_NAME

cd $STUDIO_SOURCES

yarn
yarn setup

pushd packages/api

yarn start | tee /tmp/studio-api.log
