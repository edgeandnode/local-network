#!/bin/bash
set -e

echo "Starting local-network with Indexing Payments..."

# Step 1: Initialize submodule
if [ ! -d "dipper/source/.git" ]; then
    echo "Initializing dipper submodule..."
    git submodule update --init --recursive dipper/source
fi

# Step 2: Build and start services
echo "Starting services..."
docker compose -f docker-compose.yaml -f overrides/indexing-payments/docker-compose.yaml \
  up -d

# Step 3: Wait and show status
echo "Waiting for services to become healthy..."
sleep 5
docker compose ps

echo ""
echo "Local network with Indexing Payments is running!"
echo ""
echo "Admin RPC:   http://localhost:${DIPPER_ADMIN_RPC_PORT:-9000}"
echo "Indexer RPC: http://localhost:${DIPPER_INDEXER_RPC_PORT:-9001}"
echo ""
echo "See flows/IndexingPaymentsTesting.md for testing instructions"
