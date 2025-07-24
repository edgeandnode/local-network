# DIPs Testing Flow

This guide walks through testing the Distributed Indexing Payments (DIPs) system in the local-network environment.

**What is DIPs?** DIPs (Distributed Indexing Payments) is a system for paying indexers to index specific subgraphs. Unlike query fees, DIPs payments incentivize indexers to allocate resources to index subgraphs that may not yet have query traffic.

## Prerequisites

1. All services running and healthy:
   ```bash
   docker compose ps
   ```

2. Dipper service must be built from source (private repo):
   ```bash
   git submodule update --init --recursive --force dipper/source
   # Ensure docker-compose.yaml has target: "wrapper-dev" for dipper
   docker compose up -d --build dipper
   ```

3. Source environment variables:
   ```bash
   source .env
   ```

## Setup Dipper CLI

You have two options for running the dipper CLI:

### Option 1: Use the Wrapper Script (Recommended)
```bash
# From repo root - automatically handles environment variables
./scripts/dipper-cli.sh [command]
```

### Option 2: Run from Source
```bash
cd dipper/source
# All commands will be run from this directory using cargo
# Note: You'll need to set environment variables manually (see below)
```

## Configure Authentication

**Important**: The dipper-cli requires environment variables to be set for EVERY command. You have two options:

### Option 1: Export Once per Session
```bash
# Set up DIPs CLI authentication (valid for current shell session)
source ../../.env  # Load environment from repo root
export DIPS_SIGNING_KEY="${RECEIVER_SECRET}"
export DIPS_SERVER_URL="http://localhost:${DIPPER_ADMIN_RPC_PORT}/"
```

### Option 2: Include with Each Command
```bash
# Source .env and set variables inline with each command
source ../../.env && export DIPS_SIGNING_KEY="${RECEIVER_SECRET}" && export DIPS_SERVER_URL="http://localhost:${DIPPER_ADMIN_RPC_PORT}/" && cargo run --bin dipper-cli -- [command]
```

**Note**: The CLI will fail with `missing field 'server_url'` if these environment variables are not set.

## Testing Flow

### 1. Register an Indexing Request

```bash
# Using wrapper script (from repo root):
./scripts/dipper-cli.sh requests register "QmNngXzFajkQHRj3ZjAJAF7jc2AibTQKB4dwftjiKXC9RP" 1337

# OR using cargo directly (from dipper/source):
cargo run --bin dipper-cli -- requests register "QmNngXzFajkQHRj3ZjAJAF7jc2AibTQKB4dwftjiKXC9RP" 1337

# Expected output: 
# Creating indexing request for deployment ID: DeploymentId(QmNngXzFajkQHRj3ZjAJAF7jc2AibTQKB4dwftjiKXC9RP)
# Created indexing request with ID: 01983d54-a2a0-7933-a4f5-bb96d7f4dd52
```

### 2. Verify Registration

```bash
# Using wrapper script (from repo root):
./scripts/dipper-cli.sh requests list

# OR using cargo directly (from dipper/source):
cargo run --bin dipper-cli -- requests list

# Expected output: JSON array showing your indexing request with status "OPEN"
# Example:
# [{
#   "id": "01983d54-a2a0-7933-a4f5-bb96d7f4dd52",
#   "status": "OPEN",
#   "requested_by": "0xf4ef6650e48d099a4972ea5b414dab86e1998bd3",
#   "deployment_id": "QmNngXzFajkQHRj3ZjAJAF7jc2AibTQKB4dwftjiKXC9RP"
# }]
```

### 3. Check Dipper Logs

Monitor dipper service logs for payment processing:
```bash
# Watch for indexing registration and payment activity
docker compose logs -f dipper

# Or filter for specific events:
docker compose logs -f dipper | grep -E "(payment|receipt|indexing|registered)"

# Expected log patterns:
# - "Indexing request registered"
# - "Processing payment"
# - "Receipt validated"
```

### 4. Verify Database State

Check PostgreSQL for DIPs-related data:
```bash
docker compose exec postgres psql -U postgres -d dipper -c "SELECT * FROM indexing_requests;"
```

### 5. Verify Indexer Allocation

DIPs is about paying for indexing, not queries. To verify the agreement is working, check if the indexer has allocated to the subgraph:

```bash
# Query the network subgraph to check allocations
curl -s http://localhost:8000/subgraphs/name/graph-network -X POST \
  -H 'content-type: application/json' \
  -d '{
    "query": "{ indexer(id: \"0xf4ef6650e48d099a4972ea5b414dab86e1998bd3\") { allocations { id subgraphDeployment { ipfsHash } status } } }"
  }' | jq .

# Look for an allocation with your deployment ID
# Note: This can take several minutes as the indexer-agent processes the agreement
```

**Important**: Check indexer-agent logs while waiting:
```bash
docker logs indexer-agent --tail 50 -f | grep -E "(allocation|QmNng|agreement)"
```

**Timing**: The indexer-agent runs on a cycle and may take 5-10 minutes to create the allocation after the DIPs agreement is established.

### 6. Cancel an Indexing Request

```bash
# Get the UUID from the list command
cargo run --bin dipper-cli -- requests cancel <indexing_request_uuid>

# Example:
cargo run --bin dipper-cli -- requests cancel 01983d54-a2a0-7933-a4f5-bb96d7f4dd52
```

## Verification Steps

1. **Dipper Health**: Check endpoint returns 405 (expected for root path): `curl http://localhost:9000/`
2. **Agreement Created**: Look for "Agreement proposal accepted" in dipper logs
3. **Indexer Allocation**: Query network subgraph for active allocations
4. **Indexer Agent Activity**: Monitor logs for allocation creation
5. **DIPs Flow**: Admin → Dipper → Indexer Service (port 7602) → Indexer Agent

## Common Issues

### Dipper Not Starting
- Check if submodule is initialized: `ls dipper/source/`
- Verify docker-compose.yaml has `target: "wrapper-dev"`
- Check logs: `docker compose logs dipper`
- Ensure Postgres is healthy and migrations completed

### Authentication Errors
- Verify `DIPS_SIGNING_KEY` is set correctly
- Ensure `RECEIVER_SECRET` is available in .env
- Check `DIPS_SERVER_URL` includes the port
- Try: `echo $DIPS_SIGNING_KEY` to verify it's set

### CLI Connection Issues
- Ensure dipper service is healthy: `docker compose ps dipper`
- Check admin RPC is accessible: `curl http://localhost:9000/`
- Verify port mapping in docker-compose.yaml

### Environment Variable Issues
- **"missing field 'server_url'"**: Environment variables not set
- Remember: Variables must be set for EVERY dipper-cli command
- If switching terminals/sessions, re-export the variables
- Alternative: Create a shell script that sets variables and runs commands

### No Payment Activity
- Ensure gateway is healthy and can route queries
- Verify indexer-service has the DIPs RPC port exposed (7602)
- Check that an allocation exists for the subgraph
- Look for errors in indexer-service logs: `docker compose logs indexer-service`

## Cleanup

```bash
# Stop watching logs/consumers
# Ctrl+C to exit

# Optionally restart services
docker compose restart dipper gateway
```