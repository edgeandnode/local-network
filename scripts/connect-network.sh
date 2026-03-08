#!/bin/bash
# Connect a container (typically a devcontainer) to the local-network compose network
# so that compose service names (gateway, redpanda, graph-node, etc.) resolve directly
# without needing to use localhost port mappings.
#
# Usage:
#   scripts/connect-network.sh [NETWORK_NAME]
#
# If NETWORK_NAME is omitted, the script auto-detects the compose project by finding
# a running container with label com.docker.compose.service=chain and derives the
# default network name as <project>_default.
#
# Idempotent: safe to run multiple times; exits cleanly if already connected.

if [ -n "$1" ]; then
    NETWORK="$1"
else
    PROJECT=$(docker ps --filter "label=com.docker.compose.service=chain" \
        --format '{{.Label "com.docker.compose.project"}}' | head -1)
    NETWORK="${PROJECT:-local-network}_default"
fi
CONTAINER_ID=$(hostname)

if ! docker network inspect "$NETWORK" &>/dev/null; then
    echo "Network $NETWORK not found. Run 'docker compose up' first, then re-run: connect-network.sh"
    exit 0
fi

if docker network inspect "$NETWORK" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null | grep -qw "$CONTAINER_ID"; then
    echo "Already connected to $NETWORK"
    exit 0
fi

echo "Connecting $CONTAINER_ID to $NETWORK..."
output=$(docker network connect "$NETWORK" "$CONTAINER_ID" 2>&1)
if echo "$output" | grep -q "already exists"; then
    echo "Already connected to $NETWORK"
    exit 0
elif [ -n "$output" ]; then
    echo "$output" >&2
    exit 1
fi
echo "Connected. Service names (gateway, redpanda, etc.) now resolve."
