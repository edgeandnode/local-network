#!/bin/bash
# Wrapper for dipper-cli: runs the published image (pinned in lockstep with the dipper
# server via DIPPER_VERSION) on the compose network — no local checkout or cargo build.
# The `dipper-cli` compose service supplies the signing key and admin-RPC URL.
set -eu

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/.."

exec docker compose --profile tools run --rm dipper-cli "$@"
