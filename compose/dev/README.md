# Dev Overrides

Compose override files for local development. Most mount a locally-built binary
into the running container, avoiding full image rebuilds.

## Usage

Set `COMPOSE_FILE` in `.env` (or `.env.local`) to include the override:

```bash
COMPOSE_FILE=docker-compose.yaml:compose/dev/graph-node.yaml
```

Chain multiple overrides:

```bash
COMPOSE_FILE=docker-compose.yaml:compose/dev/graph-node.yaml:compose/dev/indexer-agent.yaml
```

Then `just up` applies the overrides automatically.

## Available Overrides

| File                      | Service                          | Required Env Var                                       |
| ------------------------- | -------------------------------- | ------------------------------------------------------ |
| `graph-node.yaml`         | graph-node                       | `GRAPH_NODE_SOURCE_ROOT`                               |
| `graph-contracts.yaml`    | graph-contracts, subgraph-deploy | `CONTRACTS_SOURCE_ROOT`, `GRAPH_CONTRACTS_SOURCE_ROOT` |
| `indexer-agent.yaml`      | indexer-agent                    | `INDEXER_AGENT_SOURCE_ROOT`                            |
| `indexer-service.yaml`    | indexer-service                  | `INDEXER_SERVICE_BINARY`                               |
| `tap-agent.yaml`          | tap-agent                        | `TAP_AGENT_BINARY`                                     |
| `gateway.yaml`            | gateway                          | `GATEWAY_BINARY`                                       |
| `eligibility-oracle.yaml` | eligibility-oracle-node          | `REO_BINARY`                                           |
| `dipper.yaml`             | dipper                           | `DIPPER_BINARY`                                        |
| `iisa.yaml`               | iisa                             | `IISA_VERSION=local`                                   |
| `studio.yaml`             | studio-api, studio-ui, studio-query-proxy, studio-deployment-router | `STUDIO_SOURCE_ROOT` |

See each file's header comments for details.

## Studio (dev override)

Mounts a local `subgraph-studio` checkout at `/app` so the four studio app
services (`studio-api`, `studio-ui`, `studio-query-proxy`,
`studio-deployment-router`) run against your working tree. This override is
**required** today — no local-network-targeted subgraph-studio image is
published yet (see "Future" below). Without it, the four services start, find
no source at `/app`, and exit with a helpful message.

`studio-redis` runs unconditionally (no override needed) once the `studio`
profile is active.

**URL:** http://localhost:5000/studio/

### Prerequisites

1. Clone `subgraph-studio` — the local-Hardhat patches (chain entry, deployment
   router LOCAL mode, optional `LOCAL_*` env vars) are now on `main`.
   Then set `STUDIO_SOURCE_ROOT=/abs/path/to/subgraph-studio` in `.env` or `.env.local`.
2. From inside the studio repo, run install and build:
   ```bash
   bun install
   bun run build
   ```
3. Enable the override and the studio profile in `.env` or `.env.local` :
   ```bash
   COMPOSE_FILE=docker-compose.yaml:compose/dev/studio.yaml
   COMPOSE_PROFILES=block-oracle,explorer,studio
   STUDIO_SOURCE_ROOT=/abs/path/to/subgraph-studio
   ```

### Port 5000

`STUDIO_UI_PORT` must stay at 5000 — WalletConnect's metadata URL is
hardcoded to that port in the studio UI.

### Future: switch to a prebuilt GHCR image

The current base compose builds `containers/ui/studio/dev/Dockerfile`
(node + bun, no source baked in). It's a placeholder for an image that doesn't
exist yet. Subgraph-studio already publishes to GHCR staging and production build 
images, but both bake their URLs into the UI bundle at build time so a local network
version is still required.

Migration to image-pull mode requires a CI job on `edgeandnode/subgraph-studio`
that builds an image with `localhost`-targeted URLs and pushes it to GHCR. 
Once that exists, swap `build: { context: containers/ui/studio/dev }` in 
`docker-compose.yaml` for `image: ghcr.io/...:<tag>` and drop the dev
override + the dev/Dockerfile. The per-service `.sh` env wrappers stay.
