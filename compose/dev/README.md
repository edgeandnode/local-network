# Dev Overrides

Compose override files for local development. Most mount a locally-built binary
or source tree into the running container, avoiding full image rebuilds.

> **Prefer the image-tag approach when possible.** For services whose upstream
> repo has a `docker-compose.yml` + `just build-image` target (e.g. dipper, iisa),
> producing a `:local`-tagged image and setting the corresponding `*_VERSION=local`
> in `.env` is the primary iteration path — portable across machines, reuses the
> same consumption model as published images, and leaves no host-absolute paths
> in `.env`. These overrides are an older binary/source-mount mechanism kept for
> cases where that doesn't fit; **several have not been exercised recently and
> may not work as documented** — treat them as starting points rather than
> guaranteed-working recipes.

## Usage

Set `COMPOSE_FILE` in `.env` (or `.env.local`) to include the override:

```bash
COMPOSE_FILE=docker-compose.yaml:compose/dev/graph-node.yaml
```

Chain multiple overrides:

```bash
COMPOSE_FILE=docker-compose.yaml:compose/dev/graph-node.yaml:compose/dev/indexer-agent.yaml
```

Then `docker compose up -d` applies the overrides automatically.

## Available Overrides

| File                            | Service                  | Required Env Var               |
| ------------------------------- | ------------------------ | ------------------------------ |
| `graph-node.yaml`               | graph-node               | `GRAPH_NODE_SOURCE_ROOT`       |
| `graph-contracts-horizon.yaml`  | graph-contracts-horizon  | `CONTRACTS_SOURCE_ROOT`        |
| `graph-contracts-issuance.yaml` | graph-contracts-issuance | `CONTRACTS_SOURCE_ROOT`        |
| `network-subgraph.yaml`         | subgraph-deploy          | `NETWORK_SUBGRAPH_SOURCE_ROOT` |
| `indexer-agent.yaml`            | indexer-agent            | `INDEXER_AGENT_SOURCE_ROOT`    |
| `indexer-service.yaml`          | indexer-service          | `INDEXER_SERVICE_BINARY`       |
| `tap-agent.yaml`                | tap-agent                | `TAP_AGENT_BINARY`             |
| `eligibility-oracle.yaml`       | eligibility-oracle-node  | `REO_BINARY`                   |
| `dipper.yaml`                   | dipper                   | `DIPPER_BINARY`                |
| `iisa.yaml`                     | iisa                     | `IISA_VERSION=local`           |

See each file's header comments for details.
