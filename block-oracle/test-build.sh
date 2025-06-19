#!/bin/bash
set -euo pipefail

echo "=== Block Oracle Docker Build and Test Script ==="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

IMAGE_NAME="local-network-block-oracle"
CONTAINER_NAME="block-oracle-test"

# Function to cleanup
cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
}

# Set trap to cleanup on exit
trap cleanup EXIT

echo -e "${YELLOW}Step 1: Building Docker image...${NC}"
start_time=$(date +%s)

if docker build -t "$IMAGE_NAME" .; then
    build_time=$(($(date +%s) - start_time))
    echo -e "${GREEN}✓ Build completed successfully in ${build_time}s${NC}"
else
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 2: Checking image size...${NC}"
image_size=$(docker images "$IMAGE_NAME" --format "table {{.Size}}" | tail -n 1)
echo -e "${GREEN}Image size: ${image_size}${NC}"

echo -e "${YELLOW}Step 3: Testing basic container functionality...${NC}"

# Test 1: Check if container starts without errors
echo "Testing container startup..."
if docker run --name "$CONTAINER_NAME" -d --entrypoint="" "$IMAGE_NAME" sleep 30; then
    echo -e "${GREEN}✓ Container starts successfully${NC}"
else
    echo -e "${RED}✗ Container failed to start${NC}"
    exit 1
fi

# Test 2: Check if required binaries are available
echo "Testing required binaries..."
binaries=("pnpm" "yarn" "node" "cargo" "forge" "cast" "yq")
for binary in "${binaries[@]}"; do
    if docker exec "$CONTAINER_NAME" which "$binary" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ $binary is available${NC}"
    else
        echo -e "${RED}✗ $binary is missing${NC}"
        exit 1
    fi
done

# Test block-oracle binary separately (not in PATH)
echo "Testing block-oracle binary..."
if docker exec "$CONTAINER_NAME" test -f "/opt/block-oracle/block-oracle"; then
    echo -e "${GREEN}✓ block-oracle binary exists${NC}"
else
    echo -e "${RED}✗ block-oracle binary is missing${NC}"
    exit 1
fi

# Test 3: Check if pnpm is working properly
echo "Testing pnpm functionality..."
if docker exec "$CONTAINER_NAME" pnpm --version > /dev/null 2>&1; then
    pnpm_version=$(docker exec "$CONTAINER_NAME" pnpm --version)
    echo -e "${GREEN}✓ pnpm version: $pnpm_version${NC}"
else
    echo -e "${RED}✗ pnpm is not working${NC}"
    exit 1
fi

# Test 4: Check if Node.js packages are pre-installed
echo "Testing pre-installed dependencies..."
if docker exec "$CONTAINER_NAME" test -d "/opt/contracts/packages/data-edge/node_modules"; then
    echo -e "${GREEN}✓ Contracts dependencies are pre-installed${NC}"
else
    echo -e "${RED}✗ Contracts dependencies are missing${NC}"
    exit 1
fi

if docker exec "$CONTAINER_NAME" test -d "/opt/block-oracle/packages/subgraph/node_modules"; then
    echo -e "${GREEN}✓ Subgraph dependencies are pre-installed${NC}"
else
    echo -e "${RED}✗ Subgraph dependencies are missing${NC}"
    exit 1
fi

# Test 5: Check if block-oracle binary works
echo "Testing block-oracle binary functionality..."
if docker exec "$CONTAINER_NAME" /opt/block-oracle/block-oracle --help > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Block-oracle binary is functional${NC}"
else
    echo -e "${RED}✗ Block-oracle binary is not working${NC}"
    exit 1
fi

# Test 6: Check directory structure
echo "Testing directory structure..."
expected_dirs=("/opt/block-oracle" "/opt/contracts" "/opt/contracts/packages/data-edge")
for dir in "${expected_dirs[@]}"; do
    if docker exec "$CONTAINER_NAME" test -d "$dir"; then
        echo -e "${GREEN}✓ Directory $dir exists${NC}"
    else
        echo -e "${RED}✗ Directory $dir is missing${NC}"
        exit 1
    fi
done

echo -e "${GREEN}=== All tests passed! The optimized Docker image is working correctly ===${NC}"
echo -e "${YELLOW}Image: $IMAGE_NAME${NC}"
echo -e "${YELLOW}Size: $image_size${NC}"
echo -e "${YELLOW}Build time: ${build_time}s${NC}"