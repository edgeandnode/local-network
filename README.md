# local-network

A local Graph network for debugging & integration tests.

## Usage

Requires Docker & Docker Compose v2.24+.

```bash
# Start (or resume) the network — skips already-completed setup steps
docker compose up -d

# Re-initialise from scratch (removes all persisted state)
docker compose down -v && docker compose up -d
```

State (chain, postgres, ipfs) is persisted in named volumes, so the network
restarts where it left off. Use `down -v` only when you want a clean slate.

Add `--build` to rebuild after changes to Docker build context, including modifying `run.sh` or `Dockerfile`, or changed source code.

## Useful commands

- `docker compose up -d --build ${service}` — rebuild a single service after code changes
- `docker compose logs -f ${service}`
- `source .env`

Useful commands for each component can be found at [CHEATSHEET.md](CHEATSHEET.md)

## Local Overrides

Create `.env.local` (gitignored) to override defaults without touching `.env`:

```bash
# .env.local — your local settings
COMPOSE_PROFILES=rewards-eligibility,block-oracle,explorer,indexing-payments
GRAPH_NODE_VERSION=v0.38.0-rc1
```

Host scripts source `.env.local` automatically after `.env`.

## Service Profiles

Optional services are controlled via `COMPOSE_PROFILES` in `.env`.
By default, profiles that work out of the box are enabled:

```bash
COMPOSE_PROFILES=rewards-eligibility,block-oracle,explorer
```

Available profiles:

| Profile               | Services                          | Prerequisites              |
| --------------------- | --------------------------------- | -------------------------- |
| `block-oracle`        | block-oracle                      | none                       |
| `explorer`            | block-explorer UI                 | none                       |
| `rewards-eligibility` | eligibility-oracle-node           | none (clones from GitHub)  |
| `indexing-payments`   | dipper, iisa, iisa-scoring        | GHCR auth (below)          |

To enable all profiles, uncomment the full line in `.env`:

```bash
COMPOSE_PROFILES=rewards-eligibility,block-oracle,explorer,indexing-payments
```

### GHCR authentication (indexing-payments)

The `indexing-payments` profile pulls private images from `ghcr.io/edgeandnode`.
Create a GitHub **classic** Personal Access Token with `read:packages` scope
(https://github.com/settings/tokens — fine-grained tokens do not support packages) and log in once:

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin
```

Then set the image versions in `.env` or `.env.local`:

```bash
DIPPER_VERSION=<tag>
IISA_VERSION=<tag>
```

## Building from source - Dev overrides (compose/dev/)

For local development, mount locally-built binaries into running containers.
Set `COMPOSE_FILE` in `.env` to include dev override files:

```bash
# Mount local indexer-service binary
INDEXER_SERVICE_BINARY=/path/to/indexer-rs/target/release/indexer-service-rs
COMPOSE_FILE=docker-compose.yaml:compose/dev/indexer-service.yaml

# Multiple overrides
COMPOSE_FILE=docker-compose.yaml:compose/dev/indexer-service.yaml:compose/dev/tap-agent.yaml
```

Each override requires a binary path env var. Source repos own their own build;
local-network just wraps the published image with `run.sh` and utilities.
See [compose/dev/README.md](compose/dev/README.md) for details.

## Common issues

### `too far behind`

Gateway error:

```
ERROR graph_gateway::network::subgraph_client: network_subgraph_query_err="response too far behind"
```

This happens when subgraphs fall behind the chain head. With automine (default), this is a harmless warning during startup. Run `scripts/mine-block.sh 10` to advance blocks manually if needed.
