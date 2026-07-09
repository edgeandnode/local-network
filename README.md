# local-network

A local Graph network for debugging & integration tests.

## Usage

Requires Docker & Docker Compose v2.24+ and [just](https://github.com/casey/just).

```bash
# Show all recipes
just --list

# Start (or resume) the network — skips already-completed setup steps
just up

# Rebuild a single service after code changes
just up --build ${service}

# Get logs for a service
just logs ${service}

# Re-initialise from scratch (removes all persisted state)
just reset && just up
```

__Note__: State is persisted in named volumes, so the network restarts where it left off. Use `just reset` only when you want a clean slate.

More useful commands for each component can be found at [CHEATSHEET.md](CHEATSHEET.md).

## Configuration

The `.env` file holds all configuration and is read by three consumers:

- **docker-compose** — for `${VAR}` substitution in `docker-compose.yaml` (auto-loaded from the project directory).
- **host scripts** — scripts that run on the host source this file via `source .env`.
- **containers** — volume-mounted at `/opt/config/.env` and typically sourced by each service's `run.sh`.

## Local Overrides

Create `.env.local` (gitignored) to override defaults without touching `.env`:

```bash
# .env.local — your local settings
COMPOSE_PROFILES=rewards-eligibility,block-oracle,explorer,indexing-payments
GRAPH_NODE_VERSION=v0.38.0-rc1
```

`.env.local` overrides `.env` for:
- `docker compose` but only when invoked via `just`. Bare `docker compose` reads only `.env`.
- host scripts (typically sourced automatically after `.env`)
- it DOES NOT override `.env` for container scripts.

## Service Profiles

Optional services are controlled via `COMPOSE_PROFILES` in `.env`. By default, profiles that work out of the box are enabled:

```bash
COMPOSE_PROFILES=block-oracle,explorer
```

Available profiles:

| Profile               | Services                          | Prerequisites              |
| --------------------- | --------------------------------- | -------------------------- |
| `block-oracle`        | block-oracle                      | none                       |
| `explorer`            | block-explorer UI                 | none                       |
| `rewards-eligibility` | eligibility-oracle-node           | none (clones from GitHub)  |
| `indexing-payments`   | dipper, iisa, iisa-scoring        | GHCR auth (below)          |
| `studio`              | studio-api, studio-ui, studio-query-proxy, studio-deployment-router, studio-redis | local subgraph-studio checkout (see below) |

To enable all profiles, uncomment the full line in `.env`:

```bash
COMPOSE_PROFILES=rewards-eligibility,block-oracle,explorer,indexing-payments,studio
```

### GHCR authentication (indexing-payments)

The `indexing-payments` profile pulls private images from `ghcr.io/edgeandnode`. Create a GitHub **classic** Personal Access Token with `read:packages` scope (https://github.com/settings/tokens — fine-grained tokens do not support packages) and log in once:

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin
```

Then set the image versions in `.env` or `.env.local`:

```bash
DIPPER_VERSION=<tag>
IISA_VERSION=<tag>
```

## Building from source - Dev overrides (compose/dev/)

For local development, mount locally-built binaries into running containers. Set `COMPOSE_FILE` in `.env` (or `.env.local`, when using `just`) to include dev override files:

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

## Studio quickstart

The `studio` profile runs Subgraph Studio (UI, API, query-proxy,
deployment-router, redis) against the local chain. It currently requires a
local `subgraph-studio` checkout mounted via a dev override — no
local-targeted image is published yet. See
[compose/dev/README.md](compose/dev/README.md#studio-dev-override) for the full
rationale and the planned migration to a prebuilt image.

1. Clone `subgraph-studio`, then install and build from inside the repo:
   ```bash
   bun install
   bun run build
   ```
2. Point local-network at the checkout and enable the profile + override in
   `.env.local`:
   ```bash
   STUDIO_SOURCE_ROOT=/abs/path/to/subgraph-studio
   COMPOSE_FILE=docker-compose.yaml:compose/dev/studio.yaml
   COMPOSE_PROFILES=studio
   ```
3. Start the stack:
   ```bash
   docker compose up -d
   ```
4. Connect a wallet to the local chain (see [Wallet setup](#wallet-setup) below).
5. Seed a verified user and fund the wallet so it can sign in and publish
   without the email-confirmation prompt:
   ```bash
   ./scripts/seed-studio-user.sh <your_wallet_address>
   ./scripts/fund-wallet.sh <your_wallet_address> 1 && ./scripts/mine-block.sh
   ```
6. Open the UI at http://localhost:5000/studio/

`STUDIO_UI_PORT` must stay at 5000 — WalletConnect's metadata URL is hardcoded
to that port in the studio UI.

### Wallet setup

To sign in and publish from Studio, connect a wallet (e.g. MetaMask) to the
local chain by adding a custom network:

- **RPC URL:** `http://localhost:8545` (`CHAIN_RPC_PORT`)
- **Chain ID:** `1337` (`CHAIN_ID`)
- **Currency symbol:** ETH

Use your own test account — seed and fund that address with the scripts above.
Never connect a wallet holding real funds to a local dev chain.

**macOS note:** the UI is pinned to port 5000, which macOS AirPlay Receiver
binds by default. If http://localhost:5000/studio/ is unreachable, disable it
under System Settings → General → AirDrop & Handoff → AirPlay Receiver.

## Devcontainer usage

When running inside a devcontainer, service names (gateway, redpanda, etc.) won't resolve by default because the devcontainer is on a different Docker network. Connect it to the compose network once per session:

```bash
scripts/connect-network.sh
```

The script auto-detects the compose project network. You can also pass a network name explicitly: `scripts/connect-network.sh my-network_default`.

## Common issues

### `too far behind`

Gateway error:

```
ERROR graph_gateway::network::subgraph_client: network_subgraph_query_err="response too far behind"
```

This happens when subgraphs fall behind the chain head. With automine (default), this is a harmless warning during startup. Run `scripts/mine-block.sh 10` to advance blocks manually if needed.
