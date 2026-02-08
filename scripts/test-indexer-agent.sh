#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CONTAINER_NAME="indexer-tests-postgres"
POSTGRES_PORT=5433
POSTGRES_DB="indexer_tests"
POSTGRES_USER="testuser"
POSTGRES_PASSWORD="testpass"

echo -e "${GREEN}Starting indexer-agent test runner...${NC}"

# Function to cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    docker stop $CONTAINER_NAME 2>/dev/null || true
    docker rm $CONTAINER_NAME 2>/dev/null || true
    echo -e "${GREEN}Cleanup complete${NC}"
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Check if we're in the correct directory
if [ ! -f "docker-compose.yaml" ]; then
    echo -e "${RED}Error: Must run this script from the local-network root directory${NC}"
    exit 1
fi

# Check if indexer-agent source is initialized
if [ ! -d "indexer-agent/source/packages" ]; then
    echo -e "${RED}Error: indexer-agent source not found. Run: git submodule update --init --recursive indexer-agent/source${NC}"
    exit 1
fi

# Remove any existing test container
echo -e "${YELLOW}Removing any existing test containers...${NC}"
docker stop $CONTAINER_NAME 2>/dev/null || true
docker rm $CONTAINER_NAME 2>/dev/null || true

# Start PostgreSQL container
echo -e "${YELLOW}Starting PostgreSQL container for tests...${NC}"
docker run -d \
    --name $CONTAINER_NAME \
    -e POSTGRES_DB=$POSTGRES_DB \
    -e POSTGRES_USER=$POSTGRES_USER \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p $POSTGRES_PORT:5432 \
    postgres:13

# Wait for PostgreSQL to be ready
echo -e "${YELLOW}Waiting for PostgreSQL to be ready...${NC}"
for i in {1..30}; do
    if docker exec $CONTAINER_NAME pg_isready -U $POSTGRES_USER >/dev/null 2>&1; then
        echo -e "${GREEN}PostgreSQL is ready!${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}PostgreSQL failed to start in time${NC}"
        exit 1
    fi
    echo -n "."
    sleep 1
done

# Set environment variables
export POSTGRES_TEST_HOST=localhost
export POSTGRES_TEST_PORT=$POSTGRES_PORT
export POSTGRES_TEST_DATABASE=$POSTGRES_DB
export POSTGRES_TEST_USERNAME=$POSTGRES_USER
export POSTGRES_TEST_PASSWORD=$POSTGRES_PASSWORD
export NODE_OPTIONS="--dns-result-order=ipv4first"

# RPC Provider configuration
# Option 1: Use environment variable if already set
# Option 2: Use local chain if docker-compose is running
# Option 3: Use public Arbitrum Sepolia RPC as fallback
if [ -z "$INDEXER_TEST_JRPC_PROVIDER_URL" ]; then
    # Check if local chain is running
    if docker compose ps chain 2>/dev/null | grep -q "running\|Up"; then
        echo -e "${YELLOW}Using local chain for tests${NC}"
        export INDEXER_TEST_JRPC_PROVIDER_URL="http://localhost:8545"
    else
        echo -e "${YELLOW}Using public Arbitrum Sepolia RPC for tests${NC}"
        export INDEXER_TEST_JRPC_PROVIDER_URL="https://sepolia-rollup.arbitrum.io/rpc"
    fi
else
    echo -e "${YELLOW}Using custom RPC provider: $INDEXER_TEST_JRPC_PROVIDER_URL${NC}"
fi

# API Key for The Graph subgraph endpoints (optional - tests will use public endpoints if not set)
export INDEXER_TEST_API_KEY="${INDEXER_TEST_API_KEY:-}"

# Navigate to indexer source
cd indexer-agent/source

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}Installing dependencies...${NC}"
    yarn install --frozen-lockfile
fi

# Run tests
echo -e "${GREEN}Running indexer-agent tests...${NC}"
echo -e "${YELLOW}Test environment:${NC}"
echo "  PostgreSQL: $POSTGRES_TEST_HOST:$POSTGRES_TEST_PORT"
echo "  Database: $POSTGRES_TEST_DATABASE"
echo "  User: $POSTGRES_TEST_USERNAME"
echo "  RPC Provider: $INDEXER_TEST_JRPC_PROVIDER_URL"
if [ -n "$INDEXER_TEST_API_KEY" ]; then
    echo "  Graph API Key: [configured]"
else
    echo "  Graph API Key: [not set - using public endpoints]"
fi
echo ""

# Allow passing custom test commands
if [ $# -eq 0 ]; then
    # Default: run all tests
    yarn test:ci
else
    # Run custom test command
    yarn "$@"
fi

TEST_EXIT_CODE=$?

# Return to original directory
cd ../..

if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo -e "\n${GREEN}✓ Tests completed successfully!${NC}"
else
    echo -e "\n${RED}✗ Tests failed with exit code $TEST_EXIT_CODE${NC}"
fi

exit $TEST_EXIT_CODE