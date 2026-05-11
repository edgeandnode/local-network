# Documentation

This directory contains supplementary documentation for the local-network
project. The README at the repository root covers the recipe flow and is the
right starting point.

## Testing flows

Step-by-step guides in [flows/](./flows/):

- [IndexerAgentTesting.md](./flows/IndexerAgentTesting.md) — running the
  indexer-agent test suite against a local-network-hosted Postgres.

The Rust integration tests under [`tests/`](../tests/) cover the network's
own behaviour (allocations, eligibility, rewards, denial, REO governance) —
see [tests/README.md](../tests/README.md) for the test map.

## Usage

The set of services and pinned image versions is selected by a **recipe** in
[../recipes/](../recipes/). `just resolve <recipe>` (or `just up <recipe>`)
materialises the chosen recipe into `.env`, which `docker compose` picks up
automatically. See the project [README](../README.md#recipes) for the recipe
list.

## Documentation guidelines

See [CLAUDE.md](../CLAUDE.md) for documentation standards:

- File naming: TitleCase for markdown
- Directory organization: subdirectories by topic
- Linking: relative paths, cross-references
- Maintenance: update with code; delete obsolete docs by default
