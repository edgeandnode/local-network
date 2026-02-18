# Development Environments build on local-network

## graph-node

Graph node development works with the local network by mounting the source directory defined at `GRAPH_NODE_SOURCE_ROOT`, and builds using the `rust:latest` official rust docker image.

Build artifacts are mounted at /tmp/graph-node-docker-build (host and container), and `CARGO_HOME` is set to `/tmp/graph-node-cargo-home` to reduce build times.

### Debugging

Local debugging of the service can be enabled, allowing source-level debug with gdb or an IDE. With the env var `WAIT_FOR_DEBUG` is not an empty string, we will execute the `graph-node` binary in a gdb server exposed on :2345.

### Example vscode launch.json

```json
{
  // Use IntelliSense to learn about possible attributes.
  // Hover to view descriptions of existing attributes.
  // For more information, visit: https://go.microsoft.com/fwlink/?linkid=830387
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Attach to Remote GDB Server",
      "type": "cppdbg",
      "request": "launch",
      "program": "${workspaceFolder}/target/debug/graph-node", // Path to the binary on the local machine
      "miDebuggerServerAddress": "localhost:2345", // Address of the remote GDB server
      "miDebuggerPath": "/usr/bin/gdb", // Path to GDB on the local machine
      "cwd": "${workspaceFolder}", // Current working directory
      "environment": [],
      "externalConsole": false,
      "MIMode": "gdb",
      "setupCommands": [
        {
          "description": "Enable pretty-printing for gdb",
          "text": "-enable-pretty-printing",
          "ignoreFailures": true
        }
      ],
      "logging": {
        "engineLogging": true
      },
      "sourceFileMap": {
        "/app": "${workspaceFolder}" // Maps the /app directory in the container to the local workspace
      }
    }
  ]
}
```

If either the build or execution of the graph-node fail then we fall into a trap and pause the container using `tail -f /dev/null`.

## indexer-agent, indexer-service (ts) (Hotload Dev Environment)

This is a draft/POC of a hotload dev environment for the indexer agent. It's intended to provide a quick and easy way to iterate on the indexer codebase without having to rebuild the docker image and restart the stack.

## Usage Examples

To bring the whole stack up using the override, simply specify the override file when running `docker compose up`:

```bash
# build
INDEXER_AGENT_SOURCE_ROOT=<your indexer source root>  \
docker-compose down && \
docker compose build -f docker-compose.yaml -f overrides/indexer-agent-dev/indexer-agent-dev.yaml

# start
INDEXER_AGENT_SOURCE_ROOT=<your indexer source root>  \
docker compose up -f docker-compose.yaml -f overrides/indexer-agent-dev/indexer-agent-dev.yaml -d
```

To update the container (when making changes to the entrypoint or Dockerfile), you'll need to rebuild the image and restart the container:

```bash
# in the root of this checkout, with the local-network up and running, replace the indexer-agent with a hotload dev environment
INDEXER_AGENT_SOURCE_ROOT=<your indexer source root>  \
docker compose \
-f docker-compose.yaml \
-f overrides/indexer-agent-dev/indexer-agent-dev.yaml \
up -d --no-deps indexer-agent
```

This will apply the overrides to the indexer-agent service to the docker-compose stack running and start it.

## Network Subgraph Development

A Network Subgraph directory can be mounted to the `subgraph-deploy` container for development purposes.

To start the local network with a local Network Subgraph:

```bash
# build
GRAPH_CONTRACTS_SOURCE_ROOT=<your network subgraph source root> \
docker compose \
-f docker-compose.yaml \
-f overrides/graph-contracts/graph-contracts-dev.yaml \
build

GRAPH_CONTRACTS_SOURCE_ROOT=<your network subgraph source root> \
docker compose \
-f docker-compose.yaml \
-f overrides/graph-contracts/graph-contracts-dev.yaml \
up -d graph-contracts
```

Note that running in this mode will leave the `graph-contracts` container running so you can ssh into it for debugging/development. This might interfere with other components that depend on the container exiting. The network subgraph source is mounted into `subgraph-deploy` which handles subgraph deployment.

## Indexing Payments

Override at `indexing-payments/` adds the dipper service for indexing fee payments via GRT transfers.

**Use case:** Testing indexing payment flows without TAP allocation complexity

**Key features:**

- GRT transfers (no allocations needed)
- Receipt ID system for async processing
- 1% automatic protocol burn
- Co-exists with TAP for query fees

To start with indexing payments:

```bash
docker compose -f docker-compose.yaml -f overrides/indexing-payments/docker-compose.yaml up -d
```

See [indexing-payments/README.md](indexing-payments/README.md) for detailed usage.

## Graph Contracts Dev

Override at `graph-contracts/graph-contracts-dev.yaml` mounts a local contracts repo for WIP development without rebuilding the Docker image.

**Setup:**

```bash
# The local repo must have pnpm install and pnpm build already run
export CONTRACTS_SOURCE_ROOT=/git/graphprotocol/contracts/post-audit

docker compose -f docker-compose.yaml \
  -f overrides/graph-contracts/graph-contracts-dev.yaml \
  up -d graph-contracts
```

The local repo is mounted over `/opt/contracts`, so changes to deployment scripts take effect on the next container run without rebuilding the image.

## Eligibility Oracle

Override at `eligibility-oracle/` adds the REO node service that determines indexer rewards eligibility based on query-serving performance.

**Prerequisites:**

- REO base image built locally from the REO repo:
  ```bash
  cd /path/to/eligibility-oracle-node
  docker build -t eligibility-oracle-node .
  ```
- REO contract deployed (Phase 4 in graph-contracts)

**What it does:**

- Consumes `gateway_queries` from Redpanda
- Evaluates indexer eligibility over a rolling window
- Submits eligible indexers on-chain via `renewIndexerEligibility()`
- Creates the compacted `indexer_daily_metrics` topic on startup

To start with the eligibility oracle:

```bash
docker compose -f docker-compose.yaml -f overrides/eligibility-oracle/docker-compose.yaml up -d
```

### Dev mode (local binary)

A dev override mounts a locally-built binary, skipping image rebuild during iteration:

```bash
# Build locally first
cd /git/local/eligibility-oracle-node/eligibility-oracle-node
cargo build --release -p eligibility-oracle

export REO_BINARY=$PWD/target/release/eligibility-oracle

docker compose -f docker-compose.yaml \
  -f overrides/eligibility-oracle/docker-compose.yaml \
  -f overrides/eligibility-oracle/eligibility-oracle-dev.yaml \
  up -d eligibility-oracle-node
```

After rebuilding the binary locally, restart the container to pick up the new version:

```bash
docker compose restart eligibility-oracle-node
```

See [docs/eligibility-oracle/](../docs/eligibility-oracle/) for goal, status, and gap analysis.
