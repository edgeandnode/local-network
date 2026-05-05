# Dev Overrides

Compose override files for local development. The base `docker-compose.yaml`
brings up every service from pinned commits or images — **no local checkouts
required**. Layer one or more overrides from this directory to swap a
service to your local source.

## Two override patterns

**Source-mount + in-container build (`dips-*.yaml`)**: bind-mounts your local
checkout into the container, runs build steps inside the container at startup
(cargo build for Rust, tsx/python directly for TypeScript/Python). First start
is slow; restarts are fast thanks to a persistent build cache. No host-side
build prerequisites.

**Pre-built binary or image swap (`<service>.yaml`)**: assumes you've already
built a binary or image on the host (e.g. `cargo build --release` or
`docker compose build` in the upstream repo) and bind-mounts that single
artefact into the container. Faster iteration but requires host toolchain
and target arch alignment.

Pick whichever fits your workflow. They are not designed to be mixed for
the same service in one stack.

## Usage

Set `COMPOSE_FILE` in `.env` (or `.env.local`) to chain the base file with
overrides:

```bash
# Mount only dipper (pin everything else):
COMPOSE_FILE=docker-compose.yaml:compose/dev/dips-dipper.yaml

# Mount dipper + iisa:
COMPOSE_FILE=docker-compose.yaml:compose/dev/dips-dipper.yaml:compose/dev/dips-iisa.yaml

# Mount everything for full DIPs flow (preset):
COMPOSE_FILE=docker-compose.yaml:compose/dev/dips.yaml
```

Then `docker compose up -d` applies the overrides automatically.

## Available Overrides

### Source-mount + in-container build

| File                                  | Service(s)                       | Required Env Vars                                          |
| ------------------------------------- | -------------------------------- | ---------------------------------------------------------- |
| `dips.yaml`                           | mount-everything preset          | all of the below                                           |
| `dips-subgraph-deploy.yaml`           | subgraph-deploy                  | `INDEXING_PAYMENTS_SUBGRAPH_SOURCE_ROOT`                   |
| `dips-indexer-service.yaml`           | indexer-service                  | `INDEXER_SERVICE_SOURCE_ROOT`                              |
| `dips-indexer-agent.yaml`             | indexer-agent                    | `INDEXER_AGENT_SOURCE_ROOT`                                |
| `dips-dipper.yaml`                    | dipper                           | `DIPPER_SOURCE_ROOT`, `INDEXER_SERVICE_SOURCE_ROOT`        |
| `dips-iisa.yaml`                      | iisa, iisa-cronjob               | `IISA_SOURCE_ROOT`                                         |
| `dips-reo.yaml`                       | eligibility-oracle-node          | `REO_SOURCE_ROOT`                                          |

### Pre-built binary / image swap

| File                      | Service(s)                       | Required Env Var                                       |
| ------------------------- | -------------------------------- | ------------------------------------------------------ |
| `graph-node.yaml`         | graph-node                       | `GRAPH_NODE_SOURCE_ROOT`                               |
| `graph-contracts.yaml`    | graph-contracts, subgraph-deploy | `CONTRACTS_SOURCE_ROOT`, `GRAPH_CONTRACTS_SOURCE_ROOT` |
| `indexer-agent.yaml`      | indexer-agent                    | `INDEXER_AGENT_SOURCE_ROOT`                            |
| `indexer-service.yaml`    | indexer-service                  | `INDEXER_SERVICE_BINARY`                               |
| `tap-agent.yaml`          | tap-agent                        | `TAP_AGENT_BINARY`                                     |
| `eligibility-oracle.yaml` | eligibility-oracle-node          | `REO_BINARY`                                           |
| `dipper.yaml`             | dipper                           | `DIPPER_BINARY`                                        |
| `iisa.yaml`               | iisa                             | `IISA_VERSION=local`                                   |

See each file's header comments for details.
