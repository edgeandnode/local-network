# Testing flows

Step-by-step guides for testing local-network features and workflows.

## Available flows

### [Indexer Agent Testing](./IndexerAgentTesting.md)

Run the upstream indexer-agent test suite against a Postgres started by
`scripts/test-indexer-agent.sh`. Requires a local clone of
graphprotocol/indexer in `$INDEXER_AGENT_SOURCE_ROOT`.

## Other test coverage

- **Rust integration tests** under [`../../tests/`](../../tests/) — the network's
  own behaviour (allocations, eligibility, rewards, denial, REO governance).
  See [tests/README.md](../../tests/README.md).

## Creating new flow documentation

Include:

1. Prerequisites (services that must be running, initial state)
2. Step-by-step commands with expected outputs
3. Verification steps
4. Common issues and troubleshooting
5. Cleanup procedures
