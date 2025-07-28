# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

local-network is a complete local Graph Protocol ecosystem designed for debugging Graph Protocol components (indexer stack, gateway, contracts changes, etc) and running integration tests. It orchestrates 15+ services using Docker Compose to simulate the entire Graph Protocol stack locally.

## Architecture

### Core Services
- **chain**: Foundry-based Ethereum node (hardhat network, chain ID 1337) with pre-deployed Graph Protocol contracts
- **ipfs**: IPFS node for storing subgraph manifests and metadata
- **postgres**: Shared PostgreSQL database for indexer components and graph-node

### Indexer Stack
- **graph-node**: The Graph Protocol's query processing node (indexes subgraphs and serves queries)
- **indexer-agent**: Manages allocations and interacts with the network (uses CLI)
- **indexer-service**: Rust-based service handling cost models and pricing (built from source)
- **tap-agent**: Timeline Aggregation Protocol agent for micro-payments

### Gateway & DIPs (Distributed Indexing Payments)
- **gateway**: Routes queries to appropriate indexers with payment handling
- **dipper**: Rust service managing distributed indexing payments

### Supporting Infrastructure
- **redpanda**: Kafka-compatible message broker
- **block-oracle**: Tracks blockchain blocks
- **graph-contracts**: Deploys Graph Protocol contracts on startup
- **tap-contracts**: Deploys TAP (Timeline Aggregation Protocol) contracts
- **tap-escrow-manager**: Manages TAP escrow functionality
- **tap-aggregator**: Aggregates TAP receipts
- **subgraph-deploy**: Deploys necessary subgraphs

## Key Commands

### Starting the Network
```bash
docker compose down && docker compose up --build  # Full restart with rebuild
docker compose up -d  # Start all services
docker compose ps     # Check service status
docker compose logs -f [service]  # View logs
```

**Important for Claude Code**: When building Docker images or running `docker compose up`, always use longer timeouts (5-10 minutes) as these operations can take considerable time, especially when building from source or starting the entire network.

**Important**: The initial startup can take 5-10 minutes due to the complex dependency chain:
1. **Base services** start first: `chain`, `ipfs`, `postgres`, `redpanda`
2. **graph-node** waits for base services to be healthy
3. **graph-contracts** deploys Graph Protocol contracts (then exits)
4. **tap-contracts** deploys TAP contracts (then exits) 
5. **block-oracle** starts after TAP contracts are deployed
6. **indexer-agent** waits for block-oracle to be healthy
7. **subgraph-deploy** waits for indexer-agent (deploys subgraphs, then exits)
8. **tap-escrow-manager** waits for subgraph deployment
9. **indexer-service** waits for indexer-agent and tap-escrow-manager
10. **gateway** waits for indexer-service to be healthy
11. **dipper** waits for gateway to be healthy

Services like `graph-contracts`, `tap-contracts`, and `subgraph-deploy` run once and exit successfully.

### Building from Source
Some services can be built from source using Git submodules. To enable source builds:

1. Initialize the submodule:
   ```bash
   git submodule update --init --recursive --force [service]/source
   ```

2. Set the build target to `wrapper-dev` in docker-compose.yaml:
   ```yaml
   build: { 
     target: "wrapper-dev",  # Set to "wrapper" to use pre-built images
     context: [service],
   }
   ```

Services that support source builds:
- **indexer-agent**: Requires `indexer-agent/source` submodule (Node.js/TypeScript monorepo)
- **indexer-service**: Requires `indexer-service/source` submodule
- **dipper**: Requires `dipper/source` submodule (private repo - manual init required)

### Utility Scripts
```bash
./scripts/advance-blocks.sh  # Mine new blocks on the chain
./scripts/mine-block.sh      # Alternative block mining script (requires foundry on host)
./scripts/reload-agent.sh    # Reload indexer-agent with new allocations
```

### Database Access
```bash
docker compose exec postgres psql -U postgres  # Access PostgreSQL
# Databases: indexer, tap_agent, gateway, graph_node_1
```

## Service Details

### Indexer Agent (Node.js/TypeScript)
- Built from source at `indexer-agent/source` (graphprotocol/indexer monorepo)
- Manages allocations and interactions with the network
- Runs database migrations on startup
- Serves management API on port 7600
- Health check endpoint: http://localhost:7600/health

### Indexer Service (Rust)
- Built from source at `indexer-service/source`
- Uses indexer-service-rs v1.1.1
- Configured via environment variables
- Serves on port 7600

### Dipper (DIPs)
- Built from source at `dipper/source` (private repo - requires manual submodule init)
- Manages distributed indexing payments
- Works with redpanda for message passing
- Configured for testnet-01 DIPs channel
- Admin CLI available for managing indexings (download from GitHub Actions or run from source)

### TAP (Timeline Aggregation Protocol)
- indexer-tap-agent handles micro-payments
- Receipts stored in PostgreSQL tap_escrow_subgraph database
- Configured for 1-second receipt aggregation

## Development Workflow

1. Services include health checks - wait for healthy status before use
2. Chain starts with pre-deployed contracts at block 100
3. Indexer components share a PostgreSQL database with migrations
4. Gateway requires indexers to be synced before routing queries
5. Monitor services using exposed metrics endpoints (Prometheus format)

## Debugging Best Practices

When troubleshooting issues in local-network:

1. **Always check logs first** - Never take actions without understanding the problem:
   ```bash
   docker logs [service-name] --tail 50
   ```

2. **Look for specific error patterns** in logs:
   - Connection errors (database, other services)
   - Authentication/authorization failures
   - Missing dependencies or configuration
   - Panic messages or stack traces

3. **Ask before acting** - If you find errors or unexpected behavior:
   - Show the relevant logs to the user
   - Explain what you found
   - Ask for confirmation before taking debugging actions

4. **Document common issues** - When you solve a problem:
   - Note the symptoms
   - Document the root cause
   - Provide clear solution steps
   - Add verification steps

This approach prevents unnecessary service restarts and helps build a knowledge base of solutions.

## Common Issues & Solutions

### Services Stuck in "Created" State
When services remain in "Created" state despite dependencies being met:

1. **Check logs first** - Never blindly restart services:
   ```bash
   docker logs [service-name] --tail 50
   ```

2. **Verify dependency health**:
   ```bash
   docker compose ps  # Check only running services
   docker compose ps -a  # Check all services including exited ones
   ```

3. **Manual service cascade** - If auto-start fails, trigger services manually:
   ```bash
   docker compose up -d block-oracle  # Often the first to get stuck
   # Wait for it to be healthy, then:
   docker compose up -d indexer-agent
   # Continue with other dependent services
   ```

4. **Use single docker compose up -d** after manual fixes to start remaining services

### TAP Escrow Account Setup Issue
When services fail with "No sender found for signer" or return 402 (Payment Required):

**Symptoms**:
- indexer-service logs: `There was an error while accessing escrow account: No sender found for signer 0xf39...`
- dipper crashes with: `GraphQL request failed: bad indexers: {0xf4e...2266: BadResponse(402)}`
- Gateway can query indexers but DIPs payment flow fails

**Root Cause**: TAP escrow accounts aren't automatically created on first run

**Solution**: Restart tap-escrow-manager to trigger escrow account creation:
```bash
docker compose restart tap-escrow-manager
# Wait for escrow setup (check logs for "sender=... authorized=true")
docker compose restart indexer-service
docker compose restart dipper  # If it was crashing
```

**Verification**: tap-escrow-manager logs should show:
```
sender=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
signer=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 authorized=true
allowance=100.00000000000001
```

### Other Common Issues
- **Database migrations**: indexer-agent runs migrations on startup
- **Block advancement**: Use advance-blocks.sh if chain appears stuck (epochs are 554 blocks long)
- **Gateway errors**: Ensure indexers are properly allocated and synced
- **DIPs issues**: Check redpanda connectivity and dipper logs
- **IPFS hex digests**: Valid CID is hex digits prefixed by `f1220` (e.g., `0xd6b...` → `f1220d6b...`)

## Testing Flows

Detailed step-by-step guides for specific workflows are available in the `flows/` directory:
- [DIPs Testing](flows/dips-testing.md) - Test distributed indexing payments
- Additional flows coming soon (indexer setup, subgraph deployment, gateway testing)

## Working with Git Submodules

**Important**: This repository contains Git submodules (indexer-service/source, dipper/source). Before committing:

1. **Check your current directory**:
   ```bash
   pwd  # Verify you're in the intended repository
   git status  # Check which repository you're about to commit to
   ```

2. **Common scenarios**:
   - Main repo changes (CLAUDE.md, docker-compose.yaml, scripts/): Commit from repo root
   - Indexer-service changes: Commit from `indexer-service/source/`
   - Dipper changes: Commit from `dipper/source/`

3. **Verify before pushing**:
   - Always check `git status` to ensure you're committing to the correct repository
   - Submodule commits need to be pushed separately from main repo commits

## Environment Configuration

Key environment variables are set in docker-compose.yml. Notable patterns:
- ETHEREUM_NETWORK="hardhat" for local development
- Chain RPC: http://chain:8545
- IPFS: http://ipfs:5001
- Most services expose metrics on port 7300