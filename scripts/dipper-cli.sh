#!/bin/bash
# Wrapper script for dipper-cli that automatically sets required environment variables

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source the .env file from repo root
source "$SCRIPT_DIR/../.env"
[ -f "$SCRIPT_DIR/../.env.local" ] && source "$SCRIPT_DIR/../.env.local"

# Set required environment variables
export INDEXING_SIGNING_KEY="${RECEIVER_SECRET}"
export INDEXING_SERVER_URL="http://${DIPPER_HOST:-localhost}:${DIPPER_ADMIN_RPC_PORT}/"

# Change to dipper source directory
cd "$SCRIPT_DIR/../dipper/source"

# Run dipper-cli with all passed arguments
cargo run --bin dipper-cli -- "$@"