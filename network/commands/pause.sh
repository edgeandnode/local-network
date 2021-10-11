#!/usr/bin/env bash

set -e

########################################################################
# Run

cd $CONTRACTS_SOURCES

# Pause protocol
./cli/cli.ts protocol set controller-set-paused 1

