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

# Locate dipper source
DIPPER_SOURCE="${DIPPER_SOURCE_ROOT:-}"
if [ -z "$DIPPER_SOURCE" ] || [ ! -d "$DIPPER_SOURCE" ]; then
    echo "Error: Set DIPPER_SOURCE_ROOT to a local clone of edgeandnode/dipper." >&2
    exit 1
fi

# Use pre-built release binary; build if missing
DIPPER_BIN="$DIPPER_SOURCE/target/release/dipper-cli"
if [ ! -f "$DIPPER_BIN" ]; then
    echo "Building dipper-cli (first run, ~2 min)..." >&2
    if ! cargo build --manifest-path "$DIPPER_SOURCE/Cargo.toml" --bin dipper-cli --release; then
        echo "Error: cargo build failed" >&2
        exit 1
    fi
fi

exec "$DIPPER_BIN" "$@"
