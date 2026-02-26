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

Then `docker compose up -d` applies the overrides automatically.

## Available Overrides

| File                      | Service                          | Required Env Var                                       |
| ------------------------- | -------------------------------- | ------------------------------------------------------ |
| `graph-node.yaml`         | graph-node                       | `GRAPH_NODE_SOURCE_ROOT`                               |
| `graph-contracts.yaml`    | graph-contracts, subgraph-deploy | `CONTRACTS_SOURCE_ROOT`, `GRAPH_CONTRACTS_SOURCE_ROOT` |
| `indexer-agent.yaml`      | indexer-agent                    | `INDEXER_AGENT_SOURCE_ROOT`                            |
| `indexer-service.yaml`    | indexer-service                  | `INDEXER_SERVICE_BINARY`                               |
| `tap-agent.yaml`          | tap-agent                        | `TAP_AGENT_BINARY`                                     |
| `eligibility-oracle.yaml` | eligibility-oracle-node          | `REO_BINARY`                                           |
| `dipper.yaml`             | dipper                           | `DIPPER_BINARY`                                        |
| `iisa.yaml`               | iisa                             | `IISA_VERSION=local`                                   |
| `dips.yaml`               | indexer-service, indexer-agent    | `INDEXER_SERVICE_SOURCE_ROOT`, `INDEXER_AGENT_SOURCE_ROOT` |

See each file's header comments for details.
