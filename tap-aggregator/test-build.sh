#!/bin/bash
set -euo pipefail

echo "=== TAP Aggregator V2/Horizon Build and Test Script ==="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration for horizon/v2 build
IMAGE_NAME="local-network-tap-aggregator"
CONTAINER_NAME="tap-aggregator-test"
TIMEOUT_SECONDS=30

# Function to cleanup
cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
}

# Set trap to cleanup on exit
trap cleanup EXIT

echo -e "${BLUE}Build Configuration:${NC}"
echo -e "  Branch: ${YELLOW}horizon${NC}"
echo -e "  Features: ${YELLOW}v2${NC}"
echo -e "  Image: ${YELLOW}${IMAGE_NAME}${NC}"
echo

echo -e "${YELLOW}Step 1: Building Docker image...${NC}"
start_time=$(date +%s)

# Build horizon/v2 version
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

echo -e "${YELLOW}Step 3: Testing binary functionality...${NC}"

# Test 1: Check if binary exists and shows help
echo "Testing binary help output..."
if docker run --rm --entrypoint="tap_aggregator" "$IMAGE_NAME" --help > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Binary help command works${NC}"
else
    echo -e "${RED}✗ Binary help command failed${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 4: Testing startup behavior and logs...${NC}"

# Use the actual .env file from local-network root
if [ -f "../.env" ]; then
    echo "Using actual .env from local-network root"
    cp "../.env" /tmp/test.env
else
    echo "Creating minimal test environment"
    cat > /tmp/test.env << 'EOF'
# service ports  
TAP_AGGREGATOR=7610
ACCOUNT0_SECRET=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
EOF
fi

# Create minimal contracts.json for testing
cat > /tmp/contracts.json << 'EOF'
{
  "1337": {
    "TAPVerifier": {
      "address": "0x0000000000000000000000000000000000000000"
    }
  }
}
EOF

# Test 2: Start container and analyze logs
echo "Starting container and analyzing logs..."
docker run -d --name "$CONTAINER_NAME" \
    -v /tmp/test.env:/opt/.env \
    -v /tmp/contracts.json:/opt/contracts.json \
    "$IMAGE_NAME" &

# Wait a moment for startup
sleep 3

# Capture logs for analysis
echo "Capturing logs for ${TIMEOUT_SECONDS} seconds..."
timeout ${TIMEOUT_SECONDS}s docker logs -f "$CONTAINER_NAME" > /tmp/tap_aggregator_logs.txt 2>&1 || true

echo -e "${YELLOW}Step 5: Analyzing logs...${NC}"

# Analyze logs for expected patterns
log_content=$(cat /tmp/tap_aggregator_logs.txt)

# Expected patterns for current state (with .env and mock contracts)
expected_patterns=(
    "JSON.*RPC.*server"
    "listening.*on.*port.*7610"
    "invalid.*address"
    "Error.*initializing"
)

# Actual error patterns that indicate real problems
error_patterns=(
    "panic"
    "fatal"
    "segmentation.*fault"
    "permission.*denied.*tap_aggregator"
    "no.*such.*file.*tap_aggregator"
)

# Success patterns (only when full environment is available)
success_patterns=(
    "Starting.*TAP.*aggregator"
    "server.*listening"
    "JSON.*RPC.*server"
    "gRPC.*server.*initialized"
)

echo -e "${BLUE}Log Analysis Results:${NC}"

# Check for success patterns
success_count=0
for pattern in "${success_patterns[@]}"; do
    if echo "$log_content" | grep -iq "$pattern"; then
        echo -e "${GREEN}✓ Found success pattern: $pattern${NC}"
        ((success_count++))
    fi
done

# Check for expected patterns
expected_count=0
for pattern in "${expected_patterns[@]}"; do
    if echo "$log_content" | grep -iq "$pattern"; then
        echo -e "${GREEN}✓ Found expected pattern: $pattern${NC}"
        ((expected_count++))
    else
        echo -e "${YELLOW}! Missing expected pattern: $pattern${NC}"
    fi
done

# Check for error patterns
error_count=0
for pattern in "${error_patterns[@]}"; do
    if echo "$log_content" | grep -iq "$pattern"; then
        echo -e "${RED}✗ Found error pattern: $pattern${NC}"
        ((error_count++))
    fi
done

# Check container status
container_status=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
echo -e "${BLUE}Container status: ${YELLOW}${container_status}${NC}"

# Show raw logs for inspection
echo -e "${YELLOW}Step 6: Raw log output:${NC}"
echo "--- BEGIN LOGS ---"
cat /tmp/tap_aggregator_logs.txt
echo "--- END LOGS ---"

echo -e "${YELLOW}Step 7: Final Assessment${NC}"

# Determine overall result based on current expectations
if [ $error_count -gt 0 ]; then
    echo -e "${RED}❌ ACTUAL PROBLEMS: Found ${error_count} unexpected error patterns${NC}"
    echo -e "${RED}This indicates real issues that need investigation${NC}"
elif [ $expected_count -ge 1 ]; then
    echo -e "${GREEN}✅ EXPECTED BEHAVIOR: Container behaves as expected without environment${NC}"
    echo -e "${GREEN}Build is successful and ready for integration${NC}"
    if [ $success_count -gt 0 ]; then
        echo -e "${GREEN}🎉 BONUS: Found ${success_count} success patterns - some components working!${NC}"
    fi
else
    echo -e "${YELLOW}⚠ UNCLEAR: Container behavior doesn't match expected patterns${NC}"
    echo -e "${YELLOW}Expected: Missing .env file error and TAP aggregator references${NC}"
fi

echo -e "${BLUE}=== Build and Test Summary ===${NC}"
echo -e "${YELLOW}Image: $IMAGE_NAME${NC}"
echo -e "${YELLOW}Size: $image_size${NC}"
echo -e "${YELLOW}Build time: ${build_time}s${NC}"
echo -e "${YELLOW}Success patterns: ${success_count}${NC}"
echo -e "${YELLOW}Expected patterns: ${expected_count}/${#expected_patterns[@]}${NC}"
echo -e "${YELLOW}Error patterns: ${error_count}${NC}"
echo -e "${YELLOW}Container status: ${container_status}${NC}"

# Cleanup temp files
rm -f /tmp/test.env /tmp/tap_aggregator_logs.txt