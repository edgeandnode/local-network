# Test Plan Automation - Goal

## Objective

Automate the verification queries and commands from the indexer test plans so they are repeatable, catch schema drift early, and progressively cover more of the operational workflow.

The test plans live in [graphprotocol/contracts](https://github.com/graphprotocol/contracts) and are designed for human indexers running against Arbitrum Sepolia. This automation adapts them for the local network, where we control the full stack and can cycle through epochs in seconds.

## Source Test Plans

| Document | Scope | Tests |
|----------|-------|-------|
| [BaselineTestPlan.md](https://github.com/graphprotocol/contracts/blob/reo-testing/packages/issuance/docs/testing/reo/BaselineTestPlan.md) | Standard indexer operations (stake, provision, allocate, query, rewards) | 7 cycles, 22 tests |
| [IndexerTestGuide.md](https://github.com/graphprotocol/contracts/blob/reo-testing/packages/issuance/docs/testing/reo/IndexerTestGuide.md) | REO eligibility flows (renew, expire, deny, recover) | 5 sets, 8 tests |

## Automation Layers

Each layer builds on the previous. The goal is to move progressively from schema validation toward full operational testing.

```
Layer 0: Query Validation      ← scripts validate queries parse correctly
Layer 1: State Observation     ← scripts check network state matches expectations
Layer 2: Operational Lifecycle ← scripts drive state changes and verify outcomes
Layer 3: Timing-Dependent      ← scripts manage epoch advancement and eligibility expiry
```

### Layer 0: Query Schema Validation

**What**: Run every GraphQL verification query and `cast` command from the test plans against the live network. Check for schema errors, missing fields, invalid enum values.

**Why**: Catches the kind of bugs we found manually — `unallocatedStake` vs `availableStake`, `"ProvisionThaw"` vs `Provision`, `indexingRewardAmount` on wrong entity type. These are silent failures that would block an indexer following the docs.

**Speed**: Seconds. No state changes. Safe to run anytime.

**Scripts**:
- `scripts/test-baseline-queries.sh` — all 14 BaselineTestPlan queries
- `scripts/test-indexer-guide-queries.sh` — IndexerTestGuide queries + cast commands

### Layer 1: State Observation

**What**: After network startup, verify the expected state exists: indexer registered, provision created, allocations active, epoch progressing, subgraph synced.

**Why**: Confirms the local network initialised correctly before running operational tests. Catches deployment regressions (e.g., contract upgrade breaks address book, indexer-agent fails to register).

**Speed**: Seconds. Read-only.

**Builds on**: Layer 0 queries, filtered to check specific values (non-zero stake, Active allocations, populated URL/geoHash).

### Layer 2: Operational Lifecycle

**What**: Execute the Cycle 7 end-to-end workflow: create allocation → send queries → close allocation → verify rewards and fees. Uses `cast send` for contract interactions and the indexer management API for allocation operations.

**Why**: Validates that the full indexer operational cycle works, not just that queries parse. This is what an indexer actually does.

**Speed**: Minutes. Requires epoch advancement between steps.

**Builds on**: `advance-epoch.sh`, `query_gateway.sh`, `mine-block.sh`.

### Layer 3: Timing-Dependent Flows

**What**: Test eligibility expiry, thawing periods, and other time-dependent behaviour by advancing chain time and epochs programmatically.

**Why**: These are the hardest tests to run manually — an indexer on testnet waits hours for epochs to advance. On local network we can cycle in seconds.

**Covers**:
- IndexerTestGuide Sets 2-4 (eligible → expire → ineligible → re-renew → full rewards)
- BaselineTestPlan 2.2 (unstake thawing), 3.3-3.4 (provision thawing)

**Builds on**: `advance-epoch.sh`, `cast send` for eligibility renewal, `REO_ELIGIBILITY_PERIOD` from `.env`.

## Local Network Advantages

The local network can do things testnet can't:

| Capability | Testnet | Local |
|-----------|---------|-------|
| Advance epoch | Wait ~110 min | `./scripts/advance-epoch.sh` (seconds) |
| Control eligibility period | Fixed by coordinator | `REO_ELIGIBILITY_PERIOD` in `.env` |
| Advance chain time | Wait | `evm_increaseTime` RPC |
| Reset state | Can't | `docker compose down -v && up` |
| Full log access | Partial | All containers, all levels |

## Workflow Sequence

For each test plan update or protocol upgrade:

1. Start local network (`docker compose up -d`)
2. Run Layer 0 (`test-baseline-queries.sh`, `test-indexer-guide-queries.sh`) — catch schema issues immediately
3. Run Layer 1 (state observation) — confirm network initialised correctly
4. Run Layer 2 (operational lifecycle) — validate full cycle
5. Run Layer 3 (timing flows) — test eligibility and thawing
6. Fix any issues found, update test plans and scripts together

## Related Documentation

- [Eligibility Oracle Goal](../../eligibility-oracle/Goal.md) — REO local network integration
- [Eligibility Oracle Status](../../eligibility-oracle/Status.md) — REO implementation log
