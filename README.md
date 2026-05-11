# local-network

A local Graph network for debugging & integration tests.

Requires Docker & Docker Compose v2.24+, plus [`just`](https://github.com/casey/just)
for the entry-point commands.

## Quick start

```bash
just up           # resolve active recipe → .env, then docker compose up -d --build
just down         # docker compose down
just logs gateway # docker compose logs -f gateway
```

The first `just up` materialises a recipe (see below) into a gitignored `.env`
file. After that, bare `docker compose` commands work directly — `just up` just
chains recipe resolution + a build-aware compose up. `docker compose` halts
with a clear error if `.env` is missing.

## Recipes

A **recipe** selects which env fragments compose, which compose profiles enable,
and which image versions pin. Recipes live in [recipes/](recipes/) and reference
fragments in [config/](config/).

| Recipe              | Profile set                                       | Includes                                                                                      |
| ------------------- | ------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `baseline`          | `block-oracle,explorer,rewards-eligibility`       | Full GIP-0088 contract deployment (REO + IA + RAM) on stable image versions                   |
| `indexing-payments` | `explorer,rewards-eligibility,indexing-payments`  | Baseline + WIP DIPs services (dipper, IISA, indexing-payments subgraph, dips-fork indexer-rs) |

```bash
just recipes                 # list available recipes
just recipe-active           # show which one is currently selected
just up indexing-payments    # one-shot recipe override
echo indexing-payments > .recipe.local  # per-checkout sticky default (gitignored)
```

Recipe selection precedence: CLI arg → `RECIPE` env → `.recipe.local` →
`.recipe` (committed per-branch default) → `baseline`.

To add a recipe, create `recipes/my-recipe.json` with the fragments + override
`env` to apply. See existing JSON files for the shape.

## Local overrides

Create `.env.local` (gitignored) for machine-specific values that layer on top
of the resolved recipe — image-tag overrides, compose-profile additions, etc:

```bash
# .env.local
GRAPH_NODE_VERSION=v0.43.0
COMPOSE_PROFILES=block-oracle,explorer,rewards-eligibility,indexing-payments,my-extra
```

`.env.local` is sourced last during recipe resolution, so its values win.

## Iterating on upstream source

Most services run from prebuilt images pinned by `${SERVICE_VERSION}` vars
in [config/services.env](config/services.env) and
[config/indexing-payments.env](config/indexing-payments.env). To iterate on
upstream source, build a locally-tagged image in the upstream repo and
override the version pin in `.env.local`:

```bash
# .env.local
INDEXING_PAYMENTS_SUBGRAPH_VERSION=local
```

Then `just rebuild <service>` here to pick up the change.

How each upstream produces a `:local` tag is repo-specific. Convention is a
`just build-image` recipe that tags `<image>:local` — e.g.
graphprotocol/indexing-payments-subgraph builds
`ghcr.io/graphprotocol/indexing-payments-subgraph:local` via its `justfile`.

## Rebuilding after edits

```bash
just rebuild indexer-agent       # rebuild + restart one service
just rebuild                     # rebuild + restart all
just up                          # equivalent if recipe hasn't changed (defaults to --build)
```

`run.sh` and `Dockerfile` changes only take effect after a rebuild.

## State persistence

Volumes (`chain-data`, `postgres-data`, `ipfs-data`, `redpanda-data`,
`iisa-scores`, `config-local`) survive `just down`. To start clean:

```bash
just reset      # docker compose down -v
just up
```

## GHCR authentication (indexing-payments)

The `indexing-payments` profile pulls private images from `ghcr.io/edgeandnode`.
Create a GitHub **classic** Personal Access Token with `read:packages` scope
([fine-grained tokens don't support packages](https://github.com/settings/tokens))
and log in once:

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin
```

## Devcontainer usage

Inside a devcontainer, service names won't resolve by default because the
devcontainer is on a different Docker network. Connect once per session:

```bash
scripts/connect-network.sh
```

The script auto-detects the compose project network. Pass a name explicitly with
`scripts/connect-network.sh my-network_default`.

## Component cheatsheet

See [CHEATSHEET.md](CHEATSHEET.md) for per-component commands.

## Common issues

### `too far behind`

```
ERROR graph_gateway::network::subgraph_client: network_subgraph_query_err="response too far behind"
```

Subgraphs fell behind the chain head. With automine (default), this is harmless
during startup. `scripts/mine-block.sh 10` to advance blocks manually.

### `LOCAL_NETWORK_RECIPE is missing a value`

`.env` hasn't been generated yet. Run `just resolve` (or any `just up`).
