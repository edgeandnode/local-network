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
DIPPER_SOURCE="${DIPPER_SOURCE_ROOT:-}"
if [ -z "$DIPPER_SOURCE" ] || [ ! -d "$DIPPER_SOURCE" ]; then
    echo "Error: Set DIPPER_SOURCE_ROOT to a local clone of edgeandnode/dipper." >&2
    exit 1
fi
cd "$DIPPER_SOURCE"

# Run dipper-cli with all passed arguments
cargo run --bin dipper-cli -- "$@"
