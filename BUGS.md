# DIPs Local Testing - Bug Tracker

Open: BUG-007 (burst scale), BUG-008 (unpaid allocations). Fixed and load-bearing: BUG-001,
004, 006, 009, 010. Removed as stale (2026-07-07): BUG-002, 003, 005 — each described code
that no longer exists on this branch (the old indexer-service DIPs config fields, the retired
TAP subgraph, and the removed extra-indexer escrow-deposit step).

## BUG-001: dipper run.sh hardcodes RecurringCollector as zero address

**Status**: fixed (live in `containers/indexing-payments/dipper/run.sh`)

**Symptom**: dipper returns 503 on all admin RPC calls because it can't interact with the RecurringCollector contract.

**Root cause**: `containers/indexing-payments/dipper/run.sh` has `"recurring_collector": "0x0000000000000000000000000000000000000000"` instead of reading the deployed address from the config volume.

**Repo**: `local-network`
**Fix**: Read address from horizon.json via `contract_addr RecurringCollector.address horizon`. Applied in local-network.
**PR**: local-network fix applied, not submitted as standalone PR

## BUG-004: SubgraphService not registered as rewards issuer in RewardsManager

**Status**: fixed (live in `containers/core/graph-contracts/run.sh`)

**Symptom**: indexer-agent fails all allocation operations (reallocate, new allocations for DIPs) with `execution reverted: "Not a rewards issuer"`. The agent enters a perpetual retry loop, blocking both protocol subgraph reallocations and DIPs agreement acceptance.

**Root cause**: The `AllocationManager.stakeUsageSummary()` calls `RewardsManager.getRewards(SubgraphService, allocationId)` before executing allocation transactions. The RewardsManager checks whether the caller (SubgraphService at `0x09635F...`) is a registered rewards issuer. On a fresh local-network deploy, SubgraphService is never whitelisted in the RewardsManager, so all `getRewards` calls revert.

**Repo**: `local-network` (deploy scripts)
**Fix**: Added idempotent `RewardsManager.setSubgraphService()` call in `containers/core/graph-contracts/run.sh`. Applied in local-network.
**PR**: local-network fix applied, not submitted as standalone PR

## BUG-006: Indexer-agent pauses indexing-payments subgraph due to startup race condition

**Status**: fixed (the wait loop now lives in `containers/indexer/indexer-agent/run.sh`)

**Symptom**: Dipper's chain_listener reports "Subgraph appears stalled" and never sees on-chain `IndexingAgreementAccepted` events. Agreements that were accepted on-chain by indexer-agents expire in dipper's DB (status 5 = Expired) after `deadline_seconds` (300s). Dipper then reassesses and creates duplicate agreements, leading to over-allocation.

**Root cause**: The indexer-agent's startup script checks once for the indexing-payments subgraph deployment and sets `INDEXER_AGENT_OFFCHAIN_SUBGRAPHS` if found. On a fresh deploy, the agent starts before `subgraph-deploy` finishes deploying the indexing-payments subgraph (they run in parallel with no compose dependency). The single-shot check finds nothing (`INDEXING_PAYMENTS_DEPLOYMENT=`), the env var is never set, and the agent's `reconcileDeployments` subsequently pauses the subgraph because it has no allocation and no offchain rule.

**Repo**: `local-network`
**Fix**: Changed the single check to a wait loop (up to 3 minutes, 5s intervals) that polls for the indexing-payments subgraph before giving up.
**PR**: local-network fix applied, not submitted as standalone PR

## BUG-007: DIPs end-to-end pipeline can't fit a 50-request burst inside the 300s RCA deadline

**Status**: open — mitigated by a longer deadline; the three serialisation bottlenecks remain

**Update (2026-07-07)**: the measured numbers below predate dipper running 8 worker loops
(dipper #655), so re-measure before trusting them. Indexer PR #1234 (open) targets the
slow-start pressure point (3).

**Symptom**: Under load (50 indexing requests registered in a single burst against 6 indexers, num_candidates=3), 50 of the 150 resulting agreements expire (status 5) at the 300s mark. Successful accepts in the same burst show p99 create→accept of 4:57 and a max of 5:02 — already inches from the 300s wall. Dipper reassessment then creates 50 fresh agreements which accept successfully against the now-mostly-empty pipeline.

**Measured numbers (50-request burst on 6 indexers, 50 distinct deployments)**:

```
ACCEPTED agreements (150)             min 0:07  p50 3:30  p90 4:32  p99 4:57  max 5:02
EXPIRED  agreements (50)              ~5:06–5:16 lifetime; 40/50 had offer_tx submitted
```

The 5-minute ceiling on the successful path is what should jump out — the deadline isn't 5 minutes of slack with average behaviour, it's already the operating point.

**Root cause (three pressure points stacking)**:

1. **Dipper offer submission is single-wallet sequential.** Every `offer()` is a separate tx through one signer's nonce queue. 50 deployments × 3 candidates = 150 offers serialised through one mempool slot.
2. **Indexer-agent's `processProposal` is serial within an agent's accept loop.** `startProposalAcceptanceLoop` ticks every 5s and processes the queue one proposal at a time. With ~25 proposals per agent at 50-request scale, the queue can't drain inside 5 minutes.
3. **`graphNode.ensure` runs inside `processProposal`.** First-deploy-of-subgraph latency stacks per-agreement. Could be hoisted to run once per deployment instead of per agreement (or run earlier, e.g. when the rule is created in `ensureDipsRuleForProposal`).

Any one of these would tighten the budget; all three together break it at this scale.

**Repo**: `dipper` (offer submission), `graphprotocol/indexer` (indexer-agent accept loop and graphNode.ensure placement), `local-network` (deadline_seconds config).

**Operational mitigation applied (2026-04-29)**: Bumped `deadline_seconds` from 300 to 600 in `local-network/containers/indexing-payments/dipper/run.sh`. Doubles the available budget without touching any of the underlying serialisation. The 50-request stress test should now have meaningful headroom; in production a longer deadline is also safer than 300s under realistic load.

**Real fixes (not yet done)**: Address the three pressure points. Order from least to most invasive:

1. Move `graphNode.ensure` out of `processProposal` and into rule creation (`ensureDipsRuleForProposal`) so the cold-deploy cost happens once per deployment, not once per agreement.
2. Allow the agent's accept loop to process proposals in parallel (bounded concurrency, e.g. up to N in flight). The `acceptIndexingAgreement` call itself is independent per-proposal.
3. Batch dipper's `offer()` submissions via multicall, or accept that single-wallet nonce ordering is fundamentally serial and provision multiple signer wallets.

**PR**: not submitted; recorded for follow-up.

## BUG-008: 76 active on-chain allocations have no backing IndexingAgreement entity

**Status**: open — design agreed, implementation not started

**Symptom (observed 2026-04-29 after the 50-request burst stress test in BUG-007)**:

```
on-chain (graph-network subgraph)              226 active allocations
indexing-payments subgraph                     150 IndexingAgreement entities (all Accepted)
dipper DB                                      150 ACCEPTED + 50 EXPIRED
```

76 on-chain allocations exist with no matching IndexingAgreement entity in the indexing-payments subgraph. Cross-referenced against dipper, the (indexer, deployment) pairs of these stranded allocations all have a status-5 EXPIRED record in dipper's DB. Dipper paid exactly once per (indexer, deployment) pair (zero duplicate ACCEPTED agreements), so dipper isn't double-paying — but indexers are doing indexing work that won't be paid for. With 18 of those pairs holding 2 active allocations each, the same indexer is sometimes carrying both a paid allocation and a stranded one for the same deployment.

**Root cause**: The indexer-agent's reconciliation loop trusts that any active `dips`-basis indexing rule it carries should be satisfied by an active allocation. When something kills the originally-paired agreement (dipper expires it, dipper rejects it, the agent itself gets restarted and loses the in-flight context), the rule survives. Reconciliation then keeps the deployment allocated either by leaving the existing on-chain allocation alone or by creating a fresh one via `startService` — without an agreement backing it. The agent never queries indexing-payments-subgraph to verify "this allocation has a paying agreement"; it trusts dipper's earlier signal and never re-checks.

The architectural gap: the agent treats dipper's promises as durable invariants, but dipper can change its mind (reassessment, expiration, rejection) and the agent has no way to learn about that change after the initial accept.

**Repo**: `graphprotocol/indexer`

**Fix (proposed, not yet implemented)**: Add a periodic sweep on the indexer-agent that reconciles each `dips`-basis allocation against the indexing-payments-subgraph. Design points settled with Samuel:

- *Oracle*: indexing-payments-subgraph. Single batched query `indexingAgreements(where: { indexer: SELF })`, diff the returned set against the agent's active dips allocations.
- *Staleness guard*: read the chain timestamp from the subgraph response (`_meta.block.timestamp`). If the response's chain time is recent (e.g. within a small bound of wall-clock), trust the result. If the timestamp is days/months/years old, treat the subgraph as unreliable and skip the sweep this tick.
- *Action on miss*: disable the `dips` indexing rule, then let normal agent reconciliation close the allocation through its existing path. Don't close allocations directly from the sweep — that bypasses too much accounting.
- *What counts as a miss*: no IndexingAgreement entity for the (agreementId / indexer / deployment) tuple, or entity exists but state is not Accepted. Brief windows where chain_listener / subgraph hasn't caught up to a just-accepted allocation are filtered by the staleness guard.

This makes the agent self-protective: regardless of dipper's behaviour, the agent only keeps `dips`-basis allocations alive while the indexing-payments subgraph confirms there's a paying agreement for them. Defends against dipper bugs marking accepted agreements expired, dipper restarts losing in-flight state, stale rules surviving DB resets, and the kind of reassessment-induced orphan we're seeing here.

**PR**: not submitted; design agreed, implementation deferred.

## BUG-009: DIPs on-chain offer reverts on a fresh deploy, so no agreement is ever accepted

**Status**: fixed upstream — merged as edgeandnode/dipper #657 (2026-07-06); pins moved to `sha-67a48d5`

**Symptom (observed 2026-06-26 in CI on the `e2e` workflow)**: the `dips_agreement_acceptance` test registers an indexing request and waits 300s, but no agreement ever reaches `Accepted` (`seen: []`). The request itself succeeds (dipper returns a request id) and IISA scores one candidate, yet the agreement never appears in the indexing-payments subgraph. The same flow works on the long-lived `lnet-test` stack, where many `Accepted` agreements exist.

**Root cause (from dipper logs)**: the pipeline gets as far as the on-chain offer and then reverts.

```
reassessment diff computed ... iisa_returned_count=1 to_add_count=1
Indexer accepted proposal off-chain; submitting offer on-chain
Submitting RCA offer via RecurringAgreementManager manager=0x3347B4d9... collector=0x4A679253...
WARN Failed to submit offer on-chain, will retry  error=contract reverted with selector 0x26769f8d
reassessment diff computed ... iisa_returned_count=0          # candidate gone on the retry
WARN Agreement not in Created status, skipping offer submission  status=EXPIRED
```

So scoring and off-chain acceptance both work; only the on-chain `offer` reverts. The selector `0x26769f8d` decodes to `RecurringCollectorAgreementDeadlineElapsed(uint256 currentTimestamp, uint64 deadline)` — the agreement's acceptance deadline is already in the chain's past when the accept transaction lands. It is a `RecurringCollector` error, not a funding or authorisation failure.

**Why (decoded from dipper's chain-listener logs)**: dipper stamps each agreement's deadline as `now + deadline_seconds`. With `bypass_chain_clock_defenses = true` (local-network sets this because the test harness advances chain time via `evm_increaseTime`), `now` was read from dipper's chain listener's last-polled block timestamp. That listener idles on a hardcoded 300s poll interval until it carries a pending agreement, so on a fresh deploy it never observes the suite fast-forwarding the local chain ~9,334s (~2.6h) ahead during that idle window. It stamps `deadline = stale_ts + 600`, already thousands of seconds behind the real chain head, and the accept reverts as expired. The listener heartbeat confirms the drift: `subgraph_lag_seconds=-9334` (chain ahead of wall). The secondary effect — IISA returns 0 candidates on the retry, so dipper never re-offers — only matters because the first attempt is born-expired; fix the first attempt and acceptance succeeds. The same flow works on `lnet-test` only because nothing fast-forwards that long-lived chain, so its listener timestamp tracks wall time.

**Repo**: `dipper`. This is a real robustness gap the local-network harness surfaced: a deadline must come from live chain time, not a cached listener timestamp that can lag a fast-moving chain.

**Fix (merged)**: edgeandnode/dipper #657 adds a live chain-head timestamp read and stamps deadlines from it when the bypass is on, falling back to the persisted listener timestamp and then wall clock (warning on each step down), with unit tests over every path. Merged to dipper main 2026-07-06; local-network pins the published `sha-67a48d5` image, and the CI DIPs tests exercise the fix end to end.

## BUG-010: Harness, dipper, and escrow manager all transact from account0, so concurrent sends drop each other's transactions

**Status**: fixed (dipper wallet split + harness retry, validated in CI)

**Symptom**: Intermittent e2e failures across unrelated tests: `cast send` errors with `replacement transaction underpriced` / `replacement fee too low`, or a send that broadcasts fine but is never mined (`transaction was not confirmed within the timeout`, cast's 120s receipt wait). Observed killing `provision_lifecycle`, `stake_management`, `rewards_conditions`, `allocation_lifecycle`, and `dips_payment_collection` (CI run 28652662844: the test's first `runEpoch()` went out moments after dipper submitted its DIPs offer from the same account and never confirmed). Which test dies varies run to run, which made the suite look randomly flaky.

**Root cause**: Three uncoordinated senders share ACCOUNT0's single nonce sequence: the test harness (every `cast_send` in `tests/src/cast.rs` signs with `account0_secret`), dipper (its `signer.secret_key` was `${ACCOUNT0_SECRET}`, used for every on-chain offer), and the graph-tally-escrow-manager (escrow deposits). Two of them querying the pending nonce at the same moment produce two transactions with the same nonce; anvil keeps one and drops the other, and the loser either errors at submission or silently never mines. This was reproduced live: a manual `grantRole` send from account0 was dropped the same way while a background loop was also sending from account0.

**Repo**: `local-network`

**Fix**: Two parts, both applied. (1) Dipper gets a dedicated signing wallet (`DIPPER_ADDRESS` / `DIPPER_SECRET`, defined in `shared/lib.sh`): graph-contracts funds it and grants it the RecurringAgreementManager roles, start-indexing authorizes it as a signer on the RecurringCollector, and dipper's config signs with it — removing the busiest concurrent sender from account0's nonce space, and matching production where dipper never shares the governor key. (2) The harness retries a send that hits a nonce-collision error up to three more times with growing pauses (3s/6s/12s — dipper's 8 worker loops make the agent's transaction bursts outlast a single short pause), reporting every attempt's error if all fail. The remaining shared sender is the escrow manager, which must keep sending from account0 because account0 is the TAP payer.

**PR**: included in the e2e CI branch (`mb9/add-e2e-ci-and-dips-tests`).
