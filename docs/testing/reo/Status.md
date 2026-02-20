# Test Plan Automation - Status

> Last updated: 2026-02-20

## Current Phase: Layer 0 scripted

### Summary

Manually validated all GraphQL queries and `cast` commands from BaselineTestPlan.md and IndexerTestGuide.md against the live local network subgraph. Found and fixed 4 bugs. Captured the validation in repeatable scripts.

## Layer Progress

| Layer | Status | Scripts |
|-------|--------|---------|
| 0 - Query Validation | Done | `test-baseline-queries.sh`, `test-indexer-guide-queries.sh` |
| 1 - State Observation | Not started | — |
| 2 - Operational Lifecycle | Not started | — |
| 3 - Timing-Dependent Flows | Not started | — |

## Completed

- [x] Manual validation of all 14 BaselineTestPlan GraphQL queries
- [x] Manual validation of all IndexerTestGuide GraphQL queries
- [x] Manual validation of all IndexerTestGuide `cast` commands
- [x] Fixed 3 bugs in BaselineTestPlan.md (pushed to `reo-testing` branch)
- [x] Fixed 1 bug in IndexerTestGuide.md (pushed to `reo-testing` branch)
- [x] Created `scripts/test-baseline-queries.sh` (Layer 0)
- [x] Created `scripts/test-indexer-guide-queries.sh` (Layer 0)
- [x] Created Goal.md and Status.md

## Bugs Found and Fixed

### BaselineTestPlan.md (3 bugs)

| Bug | Tests affected | Fix |
|-----|---------------|-----|
| `unallocatedStake` field doesn't exist on Indexer | 2.1, 2.2, 3.2, 3.4, 6.1 | Changed to `availableStake` |
| `type: "ProvisionThaw"` invalid enum value | 3.3 | Changed to `type: Provision` (enum, not string) |
| `indexingRewardAmount` doesn't exist on Indexer | 6.1 | Changed to `rewardsEarned` |

### IndexerTestGuide.md (1 bug)

| Bug | Test affected | Fix |
|-----|--------------|-----|
| `subgraphDeployment { id { id } }` invalid nested scalar selection | 1.1 | Changed to `subgraphDeployment { ipfsHash }` |

## Up Next

- [ ] Layer 1: State observation script — verify network initialised correctly after `docker compose up`
- [ ] Layer 2: Operational lifecycle — automate Cycle 7 end-to-end workflow
- [ ] Layer 3: Timing flows — epoch advancement + eligibility expiry testing

## Existing Infrastructure

Scripts already available in this repo that Layer 2-3 will build on:

| Script | Purpose | Used by |
|--------|---------|---------|
| `advance-epoch.sh` | Mine blocks to advance N epochs | Layer 3 |
| `mine-block.sh` | Mine blocks with 12s time advancement | Layer 2, 3 |
| `query_gateway.sh` | Send queries through gateway | Layer 2 |
| `test-reo-eligibility.sh` | Full REO deny→allow cycle test | Layer 3 (model) |

## Gaps

### No signal on local network deployments

BaselineTestPlan test 4.1 filters for `signalledTokens_not: 0` — returns empty on local network because no curation signal is added during setup. Layer 2 could add signal as a setup step, or the filter could be relaxed for local testing.

### Explorer UI operations not scriptable

Cycles 1-2 in BaselineTestPlan use Explorer UI for staking and delegation parameters. On local network these are done by `graph-contracts` during deployment. For Layer 2, equivalent `cast send` commands against the staking contract would be needed.

### Indexer CLI not available in devcontainer

The `graph indexer` CLI commands (provisions, allocations, rules, actions) referenced throughout both test plans require the indexer CLI. These can be replaced with direct GraphQL queries to the indexer management API at `http://indexer-agent:7600/`.

---

## Log

### 2026-02-20 — Initial validation

- Ran all BaselineTestPlan queries against local network subgraph (graph-node:8000)
- Found 3 schema bugs: `unallocatedStake`, `"ProvisionThaw"`, `indexingRewardAmount` on Indexer
- Fixed all 3 in BaselineTestPlan.md, committed to `reo-testing` branch
- Ran all IndexerTestGuide queries and cast commands
- Found 1 bug: invalid nested `{ id { id } }` selection on scalar
- Fixed in IndexerTestGuide.md, committed to `reo-testing` branch
- Created Layer 0 automation scripts
- Created Goal.md and Status.md for tracking
