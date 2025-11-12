#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🧹 Cleaning local-network environment...${NC}"
echo ""

# Get the script directory and navigate to repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Stop and remove containers
echo -e "${YELLOW}Stopping and removing containers...${NC}"
docker compose down --remove-orphans

# Remove volumes (optional, ask user)
read -p "Remove Docker volumes (postgres data, etc.)? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Removing Docker volumes...${NC}"
    docker compose down --volumes
    echo -e "${GREEN}✓ Volumes removed${NC}"
else
    echo -e "${YELLOW}Skipping volume removal${NC}"
fi

# Remove generated config files
echo -e "${YELLOW}Removing generated config files...${NC}"
if [ -d "config/local" ]; then
    rm -rf config/local/*
    echo -e "${GREEN}✓ Config files removed${NC}"
else
    echo -e "${YELLOW}No config files to remove${NC}"
fi

# Prune Docker images (optional, ask user)
read -p "Remove Docker images built for this project? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Removing Docker images...${NC}"
    docker images --filter "reference=local-network-*" -q | xargs -r docker rmi -f
    echo -e "${GREEN}✓ Docker images removed${NC}"
else
    echo -e "${YELLOW}Skipping image removal${NC}"
fi

echo ""
echo -e "${GREEN}✅ Cleanup complete!${NC}"
echo -e "${YELLOW}To start fresh, run: docker compose up -d${NC}"

