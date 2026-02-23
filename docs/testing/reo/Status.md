# Test Plan Automation - Status

> Last updated: 2026-02-22

## Current Phase: Layers 0-3 complete

### Summary

All test layers are implemented and passing. 12 Rust integration tests cover network state observation, allocation lifecycle, reward collection, eligibility lifecycle, and query fee flow. Infrastructure changes enable the reward pipeline (curation signal + issuance config) and speed up epoch advancement (1s EBO polling).

## Layer Progress

| Layer | Status | Implementation |
|-------|--------|----------------|
| 0 - Query Validation | Done | `test-baseline-queries.sh`, `test-indexer-guide-queries.sh` |
| 1 - State Observation | Done | `test-baseline-state.sh` + Rust `network_state.rs` (6 tests) |
| 2 - Operational Lifecycle | Done | Rust `allocation_lifecycle.rs` (2 tests) |
| 3 - Timing-Dependent Flows | Done | Rust `eligibility.rs` (1 test), `reward_collection.rs` (1 test), `query_fees.rs` (2 tests) |

### Rust Test Suite (12 tests)

```
tests/tests/
  network_state.rs        6 tests   ~1s    read-only state checks
  allocation_lifecycle.rs 2 tests   ~38s   create/close/query lifecycle
  eligibility.rs          1 test    ~100s  eligible/ineligible/re-eligible cycle
  reward_collection.rs    1 test    ~54s   collect(IndexingRewards) → stake increase
  query_fees.rs           2 tests   ~1s    gateway receipts + escrow observability
```

Run with: `cd tests && cargo test -- --nocapture`

## Completed

- [x] Manual validation of all 14 BaselineTestPlan GraphQL queries
- [x] Manual validation of all IndexerTestGuide GraphQL queries
- [x] Manual validation of all IndexerTestGuide `cast` commands
- [x] Fixed 3 bugs in BaselineTestPlan.md (pushed to `reo-testing` branch)
- [x] Fixed 1 bug in IndexerTestGuide.md (pushed to `reo-testing` branch)
- [x] Created Layer 0 bash scripts
- [x] Created Rust test crate with `TestNetwork` helper library
- [x] Network state observation tests (Layer 1 in Rust)
- [x] Allocation lifecycle tests (Layer 2)
- [x] Deterministic eligibility lifecycle tests (Layer 3)
- [x] Reward collection via `collect(IndexingRewards)` (Layer 3)
- [x] Query fee / TAP receipt generation tests (Layer 3)
- [x] Enabled reward pipeline: curation signal + issuance config in deploy scripts
- [x] EBO polling interval reduced from 20s to 1s for faster tests

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

### Infrastructure bugs found during test development

| Bug | Impact | Fix |
|-----|--------|-----|
| No curation signal on any deployment | `accRewardsPerSignal = 0` — all rewards are zero regardless of issuance | Added `L2Curation.mint()` in `start-indexing/run.sh` |
| `issuancePerBlock` not configured | Default issuance too low for meaningful testing | Added `setIssuancePerBlock(100e18)` in `graph-contracts/run.sh` |
| `closeAllocation` returns 0 rewards when indexer ineligible | `RewardsDeniedDueToEligibility` event fires instead of `HorizonRewardsAssigned` | Tests renew eligibility before reward-dependent operations |
| `PaymentsEscrow.getBalance()` needs 3 args | Signature is `(payer, collector, receiver)` not `(payer, receiver)` | Fixed in `query_fees.rs` |
| EBO polling at 20s causes slow tests | Epoch sync takes ~2min per test with epoch advancement | Reduced `polling_interval_in_seconds` to 1 |

## Key Technical Findings

### Reward Pipeline Requirements

For indexing rewards to flow, ALL of these must be true:
1. `issuancePerBlock > 0` on RewardsManager (requires Governor = ACCOUNT1_SECRET)
2. Curation signal exists on the deployment (`signalledTokens > 0` via `L2Curation.mint()`)
3. Allocation spans multiple epochs
4. Indexer is eligible (if REO deployed) at the time of collect/close

### collect() vs closeAllocation()

`closeAllocation` calls `reclaimRewards()` which sends rewards to a reclaim address (or drops them). To route rewards to the indexer's stake, `SubgraphService.collect(indexer, PaymentTypes.IndexingRewards, data)` must be called BEFORE closing.

However, `closeAllocation` via the management API does internally handle reward collection — the `indexingRewards` field in the close response is non-zero when the indexer is eligible and curation signal exists.

The `collect_indexing_rewards` test directly calls `SubgraphService.collect()` as the indexer (RECEIVER_SECRET) and verifies the stake delta.

### Eligibility Expiry During Mining

Mining ~100 blocks for epoch advancement adds ~1200s of chain time (12s per block). With a 300s eligibility period, the indexer becomes ineligible mid-test. Tests must call `reo_renew_indexer()` before any reward-dependent operation.

### TAP Query Fee Pipeline

The TAP stack works end-to-end for receipt generation (20/20 gateway queries succeed). However:
- TAP escrow deposits are not observed (escrow balance = 0)
- TAP subgraph shows 0 escrow accounts
- This is expected — the TAP escrow manager processes asynchronously and may need longer running time

## Gaps

### ~~No signal on local network deployments~~ RESOLVED

Fixed by adding `L2Curation.mint()` in `start-indexing/run.sh` and `setIssuancePerBlock(100e18)` in `graph-contracts/run.sh`.

### Explorer UI operations not scriptable — [Task: explorer/Goal.md](../../explorer/Goal.md)

Cycles 1-2 in BaselineTestPlan use Explorer UI for staking and delegation parameters. On local network these are done by `graph-contracts` during deployment.

### ~~Test framework for Layers 2-3~~ RESOLVED

Rust test crate implemented with `TestNetwork` helper library. See [TestFramework.md](../TestFramework.md) for the evaluation that led to this choice.

### ~~Indexer CLI not available in devcontainer~~ RESOLVED

Management API at `indexer-agent:7600` covers all operations via GraphQL.

### Cold start validation pending

Tests assume an already-running network. Full validation from `docker compose down -v && docker compose up -d` → test pass has not been confirmed yet.

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

### 2026-02-20 — Layer 1 and gap resolution

- Built `test-baseline-state.sh`: 18 checks across indexer registration, provision, allocations, deployments, gateway, epoch, chain, and REO
- Investigated `graph indexer` CLI gap: CLI available via npx, but more importantly the indexer-agent management API (port 7600) exposes full GraphQL schema with all query and mutation operations
- Management API tested: `indexerRegistration`, `allocations`, `indexerDeployments`, `provisions`, `indexingRules` all work via curl
- This resolves the biggest gap for Layer 2: operational tests can use management API mutations (`createAllocation`, `closeAllocation`, `queueActions`, etc.) instead of the CLI

### 2026-02-20 — Gap investigation and task docs

- Investigated curation signal: L2Curation contract deployed, `mint()` available, ACCOUNT0 has GRT — straightforward to add to `start-indexing/run.sh`
- Investigated Graph Explorer: repo at `/git/edgeandnode/graph-explorer/`, Next.js app with Docker support, no backend API (all contract calls via Wagmi/Viem)
- Documented Explorer contract call reference: mapped UI components (SignalForm, DelegateTransactionContext, StakeForm) to equivalent `cast send` calls
- Evaluated test frameworks: Rust (cargo-nextest) recommended for Layers 2-3 given devcontainer tooling; bash retained for Layers 0-1
- Created task docs: [CurationSignal.md](./CurationSignal.md), [explorer/Goal.md](../../explorer/Goal.md), [TestFramework.md](../TestFramework.md)

### 2026-02-21 — Rust test crate and Layers 2-3

- Created Rust integration test crate (`tests/`) with `TestNetwork` helper
- Implemented `network_state.rs` (6 tests): indexer registration, provision, allocations, gateway, epoch, REO state
- Implemented `allocation_lifecycle.rs` (2 tests): create/close cycle, gateway query serving
- Implemented `eligibility.rs` (1 test): 3-phase lifecycle (eligible → ineligible → re-eligible) with deterministic contract calls
- All 9 tests passing

### 2026-02-22 — Reward pipeline and expanded coverage

- Discovered rewards were zero: `accRewardsPerSignal = 0` due to missing curation signal
- Fixed by adding `L2Curation.mint(1000 GRT)` in `start-indexing/run.sh`
- Set `issuancePerBlock = 100 GRT` in `graph-contracts/run.sh` (requires ACCOUNT1_SECRET as Governor)
- Reduced EBO polling from 20s to 1s — tests 3x faster (allocation_lifecycle 105s→38s, eligibility 277s→91s)
- Added `reward_collection.rs`: `collect(IndexingRewards)` increases stake by ~12,000 GRT
- Added `query_fees.rs`: gateway generates TAP receipts (20/20), escrow state observable
- Found and fixed eligibility expiry during mining (300s period, ~1200s chain time in 2 epoch advances)
- Fixed `PaymentsEscrow.getBalance()` signature: 3 args (payer, collector, receiver)
- All 12 tests passing
