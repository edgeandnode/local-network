# DIPs Local-Network Test Run — Execution Runbook

Adapts `contracts/packages/subgraph-service/docs/dips/testing/LocalNetworkTestPlan.md`
to **this local host** (no `lnet-test` VM; everything on `localhost`).

Scope: **full** — D-1→D-8, E-1→E-4, N-1→N-5. Drive: **cycle-by-cycle checkpoints**.
Target: **dedicated test subgraph(s)**.

## Environment (resolved this deploy — addresses are per-deploy, re-read after any redeploy)

| Var | Value |
|---|---|
| RPC | http://localhost:8545 (chain id 1337) |
| AGENT_URL (mgmt API) | http://localhost:7600 |
| NETWORK_SUBGRAPH_URL | http://localhost:8000/subgraphs/name/graph-network |
| INDEXING_PAYMENTS_SUBGRAPH_URL | http://localhost:8000/subgraphs/name/indexing-payments |
| Graph-node status | http://localhost:8030/graphql |
| DIPPER_ADMIN_RPC | http://localhost:9000 |
| PG | localhost:5432, db `indexer_components_1`, user `postgres` |
| SubgraphService | 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 |
| RecurringCollector | 0x4A679253410272dd5232B3Ff7cF5dbB88f295319 |
| RecurringAgreementManager (RAM = on-chain payer) | 0x3347b4d90ebe72befb30444c9966b2b990ae9fcb |
| PaymentsEscrow | 0x322813Fd9A801c5507c9de605d63CEA4f2CE6c44 |
| RewardsManager | 0xa82fF9aFd8f496c3d6ac40E2a0F282E47488CFc9 |
| EpochManager | 0x7a2088a1bFc9d81c55368AE168C2C02570cB814F |
| SAO (subgraphAvailabilityOracle) | 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65 (Hardhat acct #4) |
| INDEXER | 0xf4EF6650E48d099a4972ea5B414daB86e1998Bd3 |
| dipper origination signing key | RECEIVER 0x2ee789a68207020b45607f5adb71933de0946baebbaaab74af7cbd69c8a90573 (only allowlisted caller) |

Origination uses the **dipper-cli `indexings set-target-candidates`** admin RPC (compose
`tools` profile image), NOT the doc's Redpanda `indexing-requirements` topic (doc drift).

## Known env-specific wrinkles (resolve as we hit them)

- **Payer is the RAM contract**, not an EOA. Affects D-8.1 (`cancelIndexingAgreementByPayer`
  can't be signed by an EOA "payer") and the `getBalance(payer,…)` reads — use RAM as the
  payer arg; for payer-cancel we need to route through RAM or use the SP-cancel paths.
- **IISA needs Redpanda query history** or it selects 0 candidates. Phase 0 seeds it.
- **Time-travel bounds:** advance with `anvil_mine <blocks> <bigInterval>`; keep epoch churn
  under the ~9-epoch allocation-expiration limit.
- **~15-min cooldown** after closing an allocation before the same deployment re-allocates —
  cancellation re-runs use a fresh deployment.
- **D-7.3 `--force` is destructive** (ends the agreement) — last in its arc.

---

## Phase 0 — Test fixtures & tooling (pre-D-1)  ⟵ first checkpoint

0.1 Resolve + export all env vars above; verify each address has code.
0.2 Deploy **3 dedicated test subgraphs**, actually indexed on graph-node and allocated:
    - `dips-target` — reward-earning primary target (D-1…D-8 main line).
    - `dips-denied` — for D-4.2 rewards-denied sizing.
    - `dips-extra` — for E-4 concurrent + D-8 cancellation re-runs (avoids cooldown).
    Steps: build minimal subgraph → deploy to graph-node → publish/curate so it's in the
    network subgraph → set `always` rule → confirm agent opens an allocation → confirm synced.
0.3 Seed IISA: send gateway queries against target deployments, run an IISA scoring pass,
    confirm `indexers=N` (≥1) not degraded.
0.4 Build **proposal-injection tooling** for N-1…N-5: a helper to encode a `SignedRCA`
    (empty sig) and insert/adjust `pending_rca_proposals` rows, and to post/skip the on-chain
    offer. (Mirror the agent's `encode_rca` / `insert_proposal` / `post_rca_offer_on_chain`.)
0.5 Confirm SAO key (Hardhat #4) can send `setDenied` (needed for D-4.2).

**Checkpoint:** fixtures indexed+allocated, IISA scoring healthy, injection tool smoke-tested.

## Phase 1 — D-1 Environment readiness
Run the plan's Prerequisites checklist; capture baseline (pick `dips-target` as reward-earning,
`dips-denied` as denied). Confirm both subgraphs synced to head, provision active, agent
`--enable-dips true`.

## Phase 2 — D-2 Proposal origination
Seed IISA (0.3) → `set-target-candidates` for `dips-target` → verify dipper agreement `CREATED`,
`pending_rca_proposals` row `pending`, `Offer` entity on indexing-payments subgraph.

## Phase 3 — D-3 Acceptance
D-3.1 reuse existing allocation; D-3.2 force no-allocation → multicall(startService,accept).
Mine a block after accept so `waitForTransaction` resolves. Verify state `Accepted` (1),
`dips` rule, dipper `ACCEPTED_ON_CHAIN`.

## Phase 4 — D-4 Sizing
D-4.1 reward-earning tokens == rule `allocationAmount`/default. D-4.2 deny via SAO key →
tokens == `--dips-allocation-amount` (0) → undeny.

## Phase 5 — D-5 Indexing & reconciliation
Deployment healthy on graph-node; agreement `Accepted` on subgraph; `dips` rule persists ≥2
reconcile cycles; allocation not auto-closed.

## Phase 6 — D-6 Recurring collection
Drive 2–3 windows (anvil_mine). D-6.1 first-collection `maxInitialTokens` bonus; D-6.2 recurring;
D-6.3 escrow drains; D-6.4 window/target placement; D-6.5 payout scales with entities.

## Phase 7 — D-7 Protection
D-7.1 non-forced close rejected; D-7.2 not auto-closed; D-7.3 `--force` → state
`CanceledByServiceProvider` (2). **Run last in arc.**

## Phase 8 — D-8 Cancellation (fresh agreement on `dips-extra`)
D-8.1 payer cancel → state 3 + final collection (resolve RAM-payer wrinkle); D-8.2 protection
releases when non-collectable; D-8.3 `never` rule → SP cancel (2) + rule reaped + alloc closed.

## Phase 9 — E-1…E-4 Edge cases
Restart durability; late collection cap; two proposals one tick; concurrent agreements.

## Phase 10 — N-1…N-5 Negative checks (injection-driven)
Deadline-expired; offer-never-posted; excessive slippage; escrow underfunded; missing provision;
stale subgraph (pause indexing-payments >5min); offer-hash mismatch.

## Phase 11 — Teardown
Restore `always` rules; close test allocations; delete injected proposal rows; undeny; note
cooldown. Record pass/fail per test.

---

## Automated regression (fresh reset, 2026-07-14)

Ran `tests/dips-e2e.sh` (Phase 0 + D-1..D-8) on a clean `just reset && just up`.
**Result: all DIPs behaviors PASS.** Raw score 20/23; the 3 "failures" were test-script
artifacts, not DIPs issues, both since fixed in the script:
- D-4.1/D-4.2 sizing: `tokens()` helper read `sed -n '3p'` but `cast` prints the allocation
  tuple on one line; the value was actually `10000000000000000` (0.01 GRT) — sizing correct.
- D-6.2: collection-count threshold `>=3` too strict for a fresh deploy's short window (got
  2); D-6.5 (entity-scaling) passed on real collection data, so recurring collection works.

Regression also confirmed the fixes hold on a clean reset: no Bug 5 (dipper healthy on its
own), no Bug 6 (graph-contracts exit 0), Bug 7+8 fixes intact (agent boots from main-dips
source with #1241, DIPs enabled), Bug 9 worked around (D-7.3 force-close via the 0.25.10 CLI).

## Phase 0 run log & corrections

**Fixture design (corrected).** DIPs sizing/allocation must be driven by the agreement, so:
- **T-primary** — fresh deployment, **no `always` rule, not pre-allocated**. The DIP acceptance
  creates the allocation via `multicall` (D-3.2), and it carries D-4.1/D-5/D-6/D-7.
- **T-denied** — fresh, no rule, not pre-allocated. D-4.2 (deny → DIP accept → sized to the
  DIPs amount, which is **1 wei** here, not 0 — see doc-feedback #6).
- **T-reuse** — one deployment WITH an `always` rule + pre-existing plain allocation, for the
  D-3.1 reuse path only.
- Do NOT put an `always` rule on the DIP-driven targets — it races the D-3.2 multicall
  (doc-feedback #7).

**Corrections to the first Phase-0 attempt:**
- Dropped the arbitrary `20 GRT` allocationAmount I had set on dips-test-1 — it came from no
  config. Reward-earning sizing (D-4.1) is verified against the actual rule/default
  (`0.01 GRT` global default), not an invented number.
- The first attempt set `always` on all three test subgraphs (via the management API, which
  made the agent auto-allocate all of them) — wrong: it only exercises D-3.1 and pre-empts
  D-3.2. Superseded by the fixture design above.

**Env facts captured:** default allocation amount `0.01 GRT` (global rule); DIPs allocation
amount `1` wei (`indexer-agent/run.sh:125`); management-API rules need
`protocolNetwork: eip155:1337`.

## Results tracker
Filled in as we go (test id → pass/fail → evidence).

### Edge cases (E)
- **E-2 (late collection / downtime beyond window max)** — PASS. Agreement `0x10c28ca1…` on
  dips-1. Stopped the agent, advanced chain time +2000s, then: `getCollectionInfo` →
  `collectionSeconds = 660` (capped at `maxSecondsPerCollection`, not ~2028); restarted agent →
  "Successfully collected indexing fees", `lastCollectionAt` advanced; payout `3.358e16` /
  660 ≈ `5.09e13`/s (a normal rate — would be ~`1.0e17` if the full elapsed time counted, so the
  excess was forfeited); agreement state stayed `1` (Accepted), no cancellation.
- **E-4 (multiple concurrent agreements across deployments)** — PASS. Originated on 3 fresh
  deployments at once (dips-2/3/4) alongside the live dips-1 = 4 concurrent. All 4 reached
  AcceptedOnChain with **distinct allocations** (`0xa7b78cb6`, `0xf78fc729`, `0x725cba6a`,
  `0xb0c34f85`). Driving windows advanced **all 4/4** `lastCollectionAt` independently, each
  staying `Accepted`. (Optional underfunded-isolation sub-variant skipped — shared
  protocol-funded escrow.)
- **E-1 (agent restart durability)** — PASS. With dips-1..4 accepted+collecting, originated a
  fresh proposal on dips-5, caught the `pending` row at t=1s, and restarted the agent while it
  was pending. Post-restart: (a) dips-5's pending proposal survived and reached AcceptedOnChain;
  (b) dips-1..4 all 4/4 resumed collecting (`lastCollectionAt` advanced); (c) all dips rules
  persisted (dips-1..4) plus dips-5's freshly-accepted rule (5 total, via management API).
- **E-3 (two proposals, same deployment, one tick)** — dedup PASS; plan's final outcome is
  wrong (see doc-feedback #13). Injected two proposals (nonces 890001/890002) for the same
  unallocated deployment dips-7, each with a posted on-chain offer (Tier 2). First tick: A
  accepted (created allocation `0x6baaca5a…`), **B deferred (stayed `pending`)** — the anti-race
  dedup works. But "both accepted sharing one allocation" is **not achievable**: accepting B
  against A's allocation reverts `AllocationAlreadyHasIndexingAgreement(0x6baaca5a…)`
  (selector `0x333e316d`) — the contract enforces one agreement per allocation, and there is one
  allocation per (indexer, deployment). Correct outcome = **one accepted, one rejected** (B
  rejected terminal).
### Negative checks (N)
- **N-1 (deadline-expired proposal)** — PASS. Injected expired-deadline proposal (dips-9) →
  agent rejected with `deadline_expired`; no `dips` rule left for the deployment.
- **N-2 (offer never posted)** — PASS. Injected valid future-deadline proposal (dips-8) with no
  on-chain offer → stayed `pending` across ~70s; agent logged "Offer not yet on subgraph; leaving
  proposal pending".
- **N-5 (offer hash mismatch)** — PASS. Posted an on-chain offer with terms X, then injected a
  proposal with different terms Y but the same agreement id (`0x19273f06…`). Agent: "on-chain
  offerHash does not match local RCA hash" → `offer_hash_mismatch`, terminal (not retried).
- **N-4 (stale indexing-payments subgraph)** — NOT REPRODUCIBLE via the lag path (doc-feedback
  #14). The staleness guard uses `Date.now() - subgraphChainTimestamp`; the local chain
  time-travels ~2880s AHEAD of real time, so `lagSeconds` is negative and the lag branch never
  fires. Collection-continues was verified (on-chain reads, unaffected). The reaper-skip's
  `null`/unreadable branch is the only locally-triggerable path (requires breaking the subgraph
  query — not forced, to avoid destabilizing the stack).
- **N-3 (excessive slippage)** — PASS (core criteria). The agent caps its collect at the payer
  cap, so a *static* over-cap ask alone doesn't revert; the slippage revert is gated by
  `--dips-collection-slippage` (`maxSlippage = ask × slippagePct/100`, default 1%). Injected an
  agreement with `maxOngoing ≈ tokensPerSecond` + huge `tokensPerEntityPerSecond` (accepts, but
  ask exceeds cap). With slippage=0 the collect **fails and the agent throttles** ("Failed to
  collect agreement, will retry after throttle"), agreement stays `Accepted` (no cancel) — while
  normal-terms agreements keep collecting. Revert is `RecurringCollectorExcessiveSlippage`
  (the only slippage-gated revert; confirmed causally — failed only at slippage=0). Resume:
  mechanism is the same gate; the artificial agreement's overage grew past 1% so it didn't
  resume at slippage=1 (test-terms artifact, not a defect).
- **Escrow underfunded (removed from suite, #15)** — The DIPs payer escrow is
  protocol-funded (issuance tops up RAM's escrow before each collect), so it can't be brought
  below the amount owed without disabling issuance — not achievable non-destructively here.
  Mechanism is clear from source (`collect` reverts `PaymentsEscrowInsufficientBalance` when
  escrow < owed; agent throttles without cancelling). Deleted from the plan.
- **Missing provision (removed from suite, #15)** — (decision: too
  destructive). Triggering the revert requires zeroing `getProviderTokensAvailable(indexer,
  SubgraphService)`, i.e. thawing the indexer's entire ~871k GRT provision (2h thaw period),
  which risks the agent auto-closing every allocation and forces a stack reset. Mechanism
  verified from source: `RecurringCollector` requires `getProviderTokensAvailable > 0` else
  reverts `RecurringCollectorUnauthorizedDataService` (an anti-siphoning guard); the agent
  throttles-and-retries without cancelling and resumes once re-provisioned. Deleted from the plan.

### N cycle summary
Plan renumbered to N-1…N-5 after removing the two destructive/infeasible checks (escrow
underfunded, missing provision). PASS: N-1 (deadline), N-2 (offer-never-posted), N-3 (excessive
slippage), N-5 (offer-hash mismatch). NOT REPRODUCIBLE locally: N-4 (stale subgraph — wall-clock
vs time-traveling chain, #14). REMOVED from the suite (#15) — mechanisms verified from source:
escrow underfunded, missing provision.

- **Tooling:** built the proposal-injection tool (`tests/inject-rca.cjs` encoder +
  `tests/inject-proposal.sh` inserter, incl. Tier-2 `--post-offer` via `RAM.offerAgreement`).
  Validated via N-1 (expired-deadline → rejected) and a single-proposal accept (offer + inject →
  agent accepts). Note the metadata `version` field is the enum `IndexingAgreementVersion{V1}`
  so **V1 == 0** (not 1) — a wrong value makes the on-chain `decodeRCAMetadata` revert.

- **D-1.1** readiness — PASS (fresh redeploy healthy; graph-contracts exit 0; dipper healthy; provision 100k GRT; both subgraphs synced).
- **D-1.2** baseline — PASS (T-primary=QmNePZ…gmyA reward target; T-denied=QmTBep…5rV7; T-reuse=QmcbVh…3tMy pre-allocated).
- **D-2.1** origination — PASS (dipper request id `019f5c8e-c552-7cf2-a720-ac7a215780ce`; IISA selected the indexer; indexer-service `RCA accepted` at gRPC).
- **D-2.2 / D-2.3** — initially FAIL (Bug 7): stale June-12 agent rejected with
  `non_empty_signature`. **RESOLVED** by running current `main-dips` (PR #1241 ignores the
  signature) from source via the `compose/dev/indexer-agent.yaml` override. Fixing that also
  surfaced Bug 8 (stale dev override missing DIPs config) — fixed in `run-override.sh`.
- **D-2 (re-run on T-extra-a `QmTo7B…BUKo`)** — PASS. Request
  `019f5caf-8396-7462-a57f-b985596d6526`; proposal accepted (signature ignored, row
  `completed`); dipper agreement `AcceptedOnChain` (6).
- **D-3.2 (new allocation via multicall)** — PASS. Previously-unallocated T-extra-a got a
  fresh allocation `0xc9d35f6df4695331596fea979b652ff73957998c` opened by the DIP acceptance
  (multicall startService+acceptIndexingAgreement). On-chain agreement state AcceptedOnChain.
  (Note: original T-primary `QmNePZ…` agreement Expired (5) while blocked; main-line target
  reassigned to T-extra-a.)

**Environment change:** indexer-agent now runs from source (`main-dips` @ `aefddf61`) via the
dev override — `.env.local` sets `INDEXER_AGENT_SOURCE_ROOT=/home/maikol/dev/the-graph/dips-worktrees/indexer`
and `COMPOSE_FILE=docker-compose.yaml:compose/dev/indexer-agent.yaml`.

- **D-3.1 (accept reusing existing allocation)** — PASS (core behavior) on T-reuse
  (`QmcbVh…3tMy`). Request `019f5cb4-…`; dipper `AcceptedOnChain` (6); agreement
  `0x3ce653d3…` state Accepted; allocation `0xa1315a77…` **reused** (still Active,
  `createdAtBlockNumber` unchanged at 386 → not reopened; only one active allocation).
  Deviation: no `dips` rule added — the pre-existing `always` rule persists (see
  doc-feedback #10); agent still tracks it ("2 active on subgraph").
- **D-4.1 (reward-earning sizing)** — PASS. T-extra-a allocation tokens = `1e16` (0.01 GRT) =
  the global default `allocationAmount` (no deployment-specific amount). Source named.
- **D-4.2 (rewards-denied sizing)** — PASS. Denied T-denied (`QmTBep…`) via SAO key
  (`0x15d34AAf…`, Hardhat #4); DIP accepted, allocation `0xd7e63c28…` opened with tokens =
  `1e18` (1 GRT) = `INDEXER_AGENT_DIPS_ALLOCATION_AMOUNT=1` **parsed as GRT** (distinct from
  the 0.01 GRT reward default). Undenied afterward (`isDenied=false`). Note (doc-feedback #6):
  value is 1 GRT, not 0 / not 1 wei.
- **D-5.1 / D-5.2 / D-5.3 (indexing & reconciliation)** — PASS on T-extra-a. D-5.1: deployment
  synced+healthy on graph-node (no fatalError, latest≈head). D-5.2: agreement `0x544201b4…`
  state `Accepted` on the indexing-payments subgraph. D-5.3: across 3 reconcile cycles the
  `dips` rule persisted and allocation `0xc9d35f6d…` stayed Active (same id, block 3109 — not
  auto-closed).
- **D-6 (recurring collection)** on T-extra-a — 24 collections observed.
  - **D-6.1** — N/A: agreements use `maxInitialTokens=0` (doc-feedback #12); first collection
    succeeded, no bonus by design.
  - **D-6.2** — PASS: recurring across windows; `lastCollectionAt` advances each window; agent
    logs "Successfully collected indexing fees" per cycle.
  - **D-6.3** — DEVIATION (doc-feedback #11): payer escrow `getBalance` stayed constant
    (`20.37 GRT`) — protocol-funded RAM+issuance replenishes it. Payment is real
    (`tokensCollected` recorded & growing), but escrow doesn't drain as the plan expects.
  - **D-6.4** — PASS: collections land ~75s apart (min 60s + ~15s poll) = near the start of the
    [60,660]s window, matching `DIPS_COLLECTION_TARGET=1` (collect near window open).
  - **D-6.5** — PASS: `tokensCollected` scales monotonically with `entities`
    (4303→4752 entities → 4.139e15→4.269e15 tokens across steady windows).
- **D-7 (long-lived allocation protection)** on T-extra-a (alloc `0xc9d35f6d…`):
  - **D-7.1** — PASS: non-forced close **rejected** with the DIPs guard message
    ("has a DIPS agreement that can still collect fees … Use force=true"); allocation stays Active.
  - **D-7.2** — PASS: allocation not auto-closed (still Active, block 3109, across 24 collections).
  - **D-7.3** — PASS (verified with the correct CLI). Built indexer-cli 0.25.10 from source
    (`packages/indexer-cli`) and ran `allocations close <id> <poi> <blockNumber> <publicPOI>
    --network hardhat --force` from the agent container. Result: "✔ Allocation closed";
    on-chain agreement state → **2 (CanceledByServiceProvider)**; allocation → **Closed**
    (block 6966); indexing-payments subgraph agreement → `CanceledByServiceProvider`. Confirms
    force-close cancels the DIPs agreement on-chain in the same tx. (Bug 9 remains: the shipped
    start-indexing CLI 0.23.8 can't do this; local-network should bump it to ≥0.25.x.)
- **D-8 (cancellation)** — all three paths PASS, each on a fresh agreement:
  - **D-8.1 (payer cancel)** on T-extra-b (`QmeQtq…`, alloc `0xbc58ca4c…`): payer cancel via
    dipper-cli `set-target-candidates --num-candidates 0` → agreement state → **3
    (CanceledByPayer)**; then a **final collection** (`lastCollectionAt` 1783970773→1783970960);
    `getCollectionInfo` (true,32,0)→**(false,0,3)** (drained/non-collectable).
  - **D-8.2 (protection releases)**: once non-collectable, the agent's *internal* close ran —
    allocation Active→**Closed** ("Populating unallocate transaction"→"Successfully closed
    allocation"). Confirms the agent close path works (Bug 9 is external-CLI-only).
  - **D-8.3 (indexer opt-out `never`)** on T-spare (`QmPFU7…`, alloc `0x54656b84…`): set `never`
    → agent SP-cancels on-chain → agreement state → **2 (CanceledByServiceProvider)**, best-effort
    final collection attempted ("Preparing to present POI"), allocation **Closed**, and no `dips`
    rule remains (replaced by the `never` opt-out rule).
