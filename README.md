# local-network

A local Graph network for debugging & integration tests.

Epochs are set up to be 554 blocks long, use `scripts/mine-block.sh` to advance (foundry installation required)

## Notes

- The network id for manifests is `hardhat`.

## Usage

Requires Docker & Docker Compose v2.24+. Install foundry on the host for mining blocks.

```bash
# Start (or resume) the network — skips already-completed setup steps
docker compose up -d

# Re-initialise from scratch (removes all persisted state)
docker compose down -v && docker compose up -d
```

State (chain, postgres, ipfs) is persisted in named volumes, so the network
restarts where it left off. Use `down -v` only when you want a clean slate.

Add `--build` to rebuild after changes to Docker build context, including modifying `run.sh` or `Dockerfile`, or changed source code.

## Local Overrides

Create `.env.local` (gitignored) to override defaults without touching `.env`:

```bash
# .env.local — your local settings
COMPOSE_PROFILES=rewards-eligibility,block-oracle,explorer,indexing-payments
GRAPH_NODE_VERSION=v0.38.0-rc1
```

Host scripts source `.env.local` automatically after `.env`.

## Useful commands

- `docker compose up -d --build ${service}` — rebuild a single service after code changes
- `docker compose logs -f ${service}`
- `source .env`

## Components

### chain

- Foundry docs: https://book.getfoundry.sh/
- Automine: blocks are mined instantly on each transaction
- Chain state persists across restarts via `--state` flag
- Use `scripts/mine-block.sh` to manually advance blocks if needed

### block-explorer

- [esplr](https://github.com/paulmillr/esplr) block explorer available at: http://localhost:3000

### ipfs

- cat file via curl:
  ```bash
  curl -X POST "http://localhost:5001/api/v0/cat?arg=f1220d6b169dcf83bfe0f615baa2d83e9adf77d520b52faf18a759eb7277b6d66fa7f"
  ```
- cat file via CLI:
  ```bash
  ipfs --api=/ip4/127.0.0.1/tcp/5001 cat QmagRyTMp4qcRb8fJufk7urNwCQmmUEB9mC6nxHQuKwydb
  ```
- note: if you have a hex digest, a valid CID for it is the hex digits prefixed by `f1220`. For example, `0xd6b169dcf83bfe0f615baa2d83e9adf77d520b52faf18a759eb7277b6d66fa7f` -> `f1220d6b169dcf83bfe0f615baa2d83e9adf77d520b52faf18a759eb7277b6d66fa7f`

### postgres

- `psql -h localhost -U postgres`

### graph-node

- GraphiQL interface: http://localhost:8000/subgraphs/name/${subgraph_name}/graphql
- Status endpoint: http://localhost:8030/graphql/playground

### graph-contracts / subgraph-deploy

- network subgraph: http://localhost:8000/subgraphs/name/graph-network

  ```graphql
  {
    indexers {
      id
      url
      geoHash
    }
    provisions {
      id
      indexer {
        id
        stakedTokens
      }
      tokensProvisioned
      thawingPeriod
      maxVerifierCut
      dataService {
        id
        totalTokensProvisioned
      }
    }
    subgraphs {
      id
      versions {
        subgraphDeployment {
          ipfsHash
          indexerAllocations {
            id
            status
            indexer {
              id
            }
          }
        }
      }
    }
    _meta {
      block {
        number
      }
      deployment
    }
  }
  ```

### block-oracle

- subgraph: http://localhost:8000/subgraphs/name/block-oracle

  ```graphql
  {
    networks {
      id
    }
    _meta {
      block {
        number
      }
      deployment
    }
  }
  ```

### indexer-agent

- `graph indexer connect http://localhost:7600`
- `graph indexer --network=hardhat status`

### indexer-service

- `docker compose up --build indexer-service`
- `docker compose down indexer-service`
- `docker compose logs -f indexer-service`

```bash
curl "http://localhost:7601/subgraphs/id/QmRcucmbxAXLaAZkkCR8Bdj1X7QGPLjfRmQ5H6tFhGqiHX" \
  -H 'content-type: application/json' -H "Authorization: Bearer freestuff" \
  -d '{"query": "{ _meta { block { number } } }"}'
```

### gateway

```bash
curl "http://localhost:7700/api/subgraphs/id/BFr2mx7FgkJ36Y6pE5BiXs1KmNUmVDCnL82KUSdcLW1g" \
  -H 'content-type: application/json' -H "Authorization: Bearer deadbeefdeadbeefdeadbeefdeadbeef" \
  -d '{"query": "{ _meta { block { number } } }"}'
```

### redpanda

```bash
docker exec -it redpanda rpk topic consume gateway_client_query_results --brokers="localhost:9092"
```

### TAP subgraph

- subgraph: http://localhost:8000/subgraphs/name/semiotic/tap

  ```graphql
  {
    escrowAccounts {
      balance
      sender {
        id
      }
      receiver {
        id
      }
    }
    _meta {
      block {
        number
      }
      deployment
    }
  }
  ```

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

## Building Components from Source

### Dev overrides (compose/dev/)

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
