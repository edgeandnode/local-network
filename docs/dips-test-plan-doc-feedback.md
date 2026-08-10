# DIPs Test-Plan Doc Feedback

Issues found while executing the contracts-repo DIPs test plan against local-network.
Source docs live in `graphprotocol/contracts` →
`packages/subgraph-service/docs/dips/testing/` (branch `mde/dips-integration-testing-docs`).
Fix these upstream after the run.

Status legend: **confirmed** (reproduced) · **to-verify** (suspected, not yet hit in the run).

---

## 1. Origination mechanism is wrong for the current dipper — confirmed

- **Doc:** `LocalNetworkTestPlan.md` D-2.1 says produce a message to the Redpanda
  `indexing-requirements` topic to trigger origination.
- **Reality (dipper `sha-cb89726`):** origination is driven by the dipper-cli admin RPC
  `indexings set-target-candidates <deployment> <chainId> --num-candidates N`
  (signing key = RECEIVER `0xf4EF6650…`, the only allowlisted caller). There is no
  `indexing-requirements` consumer path in this build.
- **Fix:** replace the D-2.1 Redpanda snippet with the dipper-cli `set-target-candidates`
  flow (and note the IISA query-history prerequisite, see #4).

## 2. `just up indexing-payments` is not a valid command here — confirmed

- **Doc:** `LocalNetworkDetails.md` line 7 — "Bring it up with the `indexing-payments`
  recipe: `just up indexing-payments`".
- **Reality:** this repo's `up` recipe forwards args to `docker compose up -d <args>`, so
  `just up indexing-payments` resolves to a **service** named `indexing-payments`, which
  doesn't exist. The profile is enabled via `COMPOSE_PROFILES=…,indexing-payments` in `.env`
  (or `.env.local`), then a plain `just up`.
- **Fix:** correct the bring-up instruction to set the profile in `.env`/`.env.local`, not a
  `just up <recipe>` arg.

## 3. Payer-cancel (D-8.1) assumes an EOA payer, but the payer is the RAM contract — confirmed (mechanism), cancel path to-verify

- **Doc:** `LocalNetworkTestPlan.md` D-8.1 —
  `cast send --private-key "$PAYER_SECRET" "$SUBGRAPH_SERVICE" "cancelIndexingAgreementByPayer(bytes16)" …`
- **Reality:** the on-chain `payer` is the `RecurringAgreementManager` (RAM) contract
  (`0x3347…`), not an EOA — dipper offers via RAM using `AGREEMENT_MANAGER_ROLE`. There is no
  `$PAYER_SECRET` that can sign as the payer; a payer-side cancel must be routed through RAM.
- **Fix:** describe payer-cancel via RAM (or the appropriate role-holder call), and drop the
  `$PAYER_SECRET` EOA assumption. Confirm the exact RAM method during D-8.

## 4. IISA query-history prerequisite is undocumented — confirmed

- **Doc:** D-2 lists dipper/IISA "running" as the only origination prerequisite.
- **Reality:** IISA only selects indexers that have Redpanda **query history**; on a fresh
  deploy it scores in degraded mode / 0 candidates, so origination yields no proposal until
  gateway queries are sent and an IISA scoring pass runs.
- **Fix:** add a prerequisite step: seed gateway query traffic + run an IISA scoring pass
  before D-2.

## 5. "escrow funding service (TBD)" is now concrete — to-verify

- **Doc:** `LocalNetworkDetails.md` services table lists "escrow funding service (TBD)".
- **Reality:** query-payment escrow/signer auth is `graph-tally-escrow-manager`; DIPs payer
  escrow is topped up via issuance/RAM. Name them once verified during collection (D-6).

---

## 6. DIPs rewards-denied allocation amount: doc says 0, local config is 1 wei — confirmed

- **Doc:** `LocalNetworkTestPlan.md` D-4.2 — "`--dips-allocation-amount` (env
  `INDEXER_AGENT_DIPS_ALLOCATION_AMOUNT`), default `0`. A zero-token allocation is valid."
- **Reality (local-network):** `containers/indexer/indexer-agent/run.sh:125` sets
  `INDEXER_AGENT_DIPS_ALLOCATION_AMOUNT=1`. **Verified in D-4.2:** the denied deployment's
  allocation came out to `1e18` wei = **1 GRT** — i.e. the value is parsed as a **GRT amount**,
  not wei. So the denied-variant allocation sizes to 1 GRT here, not `0` and not `1 wei`. The
  pass criterion should read "equals `--dips-allocation-amount` (here 1 GRT)", and note the
  GRT (not wei) interpretation; and/or local-network should set it to `0` to match the doc's
  documented default and the "zero-token allocation is valid" claim.

## 7. D-1.2 (target has `always` rule) races D-3.2 (new allocation via multicall) — confirmed by design

- **Doc:** D-1.2 says pick the reward-earning target as a deployment with an `always` rule;
  D-3.2 says that same target must have **no active allocation** so the DIP acceptance opens
  one via `multicall(startService, acceptIndexingAgreement)`.
- **Conflict:** an `always` rule makes the agent's normal reconcile continuously (re)open a
  plain allocation, which races/pre-empts the DIP multicall — you can't stably hold
  "`always` rule + no allocation". A clean DIP-driven target should have **no `always` rule**;
  the accepted agreement creates a `dips` rule that drives indexing+allocation.
- **Fix:** split the fixtures in the plan — a **reuse target** (pre-allocated, for D-3.1) and a
  separate **DIP-driven target** (no rule, no allocation, for D-3.2 and the D-4→D-7 lifecycle).
  "Reward-earning" only means *not denied*; it does not require an `always` rule.

## 8. Setting an indexing rule via the management API requires `protocolNetwork` — confirmed

- **Doc/toolbox:** indexing-rule examples don't mention `protocolNetwork`.
- **Reality:** `setIndexingRule` mutation requires `protocolNetwork: "eip155:1337"` (CAIP-2);
  omitting it errors `Field "protocolNetwork" of required type "String!" was not provided`.
  (The `graph indexer rules` CLI supplies it via `--network`; direct API callers must include
  it.)

## 9. IISA selection mechanics are undocumented (query-history requirement + unsynced pool) — confirmed from source

- **Doc:** D-2 treats "dipper and IISA running; IISA can select the target indexer" as a given,
  with no explanation of what makes an indexer selectable.
- **Reality (verified in `iisa` src, `iisa_http_endpoints.py` + `indexer_selection.py`):**
  IISA selection uses two independent inputs:
  1. **Per-indexer quality history** (`_state.history`): stake-to-fees, latency, uptime,
     success-rate, price — keyed by **indexer address**, derived from gateway query traffic in
     the `gateway_queries` Redpanda topic. An indexer with **no** query history is absent from
     `history` and cannot be selected at all. The traffic can be for **any** subgraph — it is
     not per-target-deployment. (Hence the seeding step: send gateway queries so the indexer is
     scored.)
  2. **Per-deployment synced set** (`sync_status_loader`, deployment → synced indexers): used as
     a **preference, not a gate**. Candidates split into a "synced" pool and an "unsynced" pool;
     an unsynced indexer still "competes on merit in the unsynced pool" (`indexer_selection.py`
     ~546–573). This is what lets DIPs onboard an indexer onto a deployment it does **not** yet
     serve — critical, and non-obvious.
  - There is also a **price pre-filter** (`_filter_by_price`): an indexer whose advertised DIPs
     price exceeds the request's `max_grt_per_30_days` is dropped before scoring.
- **Fix:** add a D-2 prerequisite documenting (a) seed gateway query history so the indexer is
  scored, (b) the indexer need not already index the target (unsynced pool), (c) the indexer's
  advertised price must be under the request ceiling.

## 10. D-3.1 "a `dips` rule exists" is environment-dependent — not true when the reused allocation came from an `always` rule — confirmed

- **Doc:** `LocalNetworkTestPlan.md` D-3.1 pass criteria include "A `dips` indexing rule exists
  for the deployment — `decisionBasis == "dips"`".
- **Reality:** the natural way to pre-open an allocation in local-network (so there is one to
  reuse) is to set an `always` rule. After the DIP is accepted against that allocation, the
  agent **keeps the `always` rule and does NOT add a `dips` rule** — yet it still tracks the
  agreement (agent logs "Ensuring DIPS indexing rules: … 2 active on subgraph, 2 unique
  deployments"; on-chain agreement `Accepted`; allocation reused, `createdAtBlockNumber`
  unchanged). The `dips` rule only appears when the deployment had **no** prior rule (D-3.2).
- **Fix.** Either (a) reword D-3.1 to require "the deployment is tracked as a DIPs agreement
  (active on subgraph / on-chain `Accepted`)" rather than specifically a `dips` rule, noting
  that a pre-existing `always` rule is left in place; or (b) have D-3.1 open the reusable
  allocation by a means other than an `always` rule so a `dips` rule is genuinely added. Also
  clarify that rule-based criteria in D-5.3 / D-8.3 apply to the D-3.2 (no-prior-rule) target,
  not the `always`-seeded reuse target.

## 11. D-6.3 "escrow drains cumulatively" doesn't hold in the protocol-funded flow — confirmed

- **Doc:** `LocalNetworkTestPlan.md` D-6.3 — "The payer escrow balance decreases with each
  collection … re-run `getBalance` per cycle and compare."
- **Reality:** on local-network the payer is the `RecurringAgreementManager` and escrow is
  **replenished by issuance** (graph-contracts routes 6 GRT/block to RAM, which tops up escrow
  before collection). Observed: `getBalance(RAM, RC, indexer)` stayed **bit-identical**
  (`20370370370370372000`) across 3 driven windows even though 6 collections landed in that
  span (24 total). Payment is real — `indexingFeeCollections.tokensCollected` is recorded and
  grows per collection — but the payer-side escrow does **not** monotonically drain.
- **Fix.** For the protocol-funded (RAM + issuance) configuration, D-6.3 should verify
  cumulative **`tokensCollected`** increasing (or the indexer's received total), not payer
  escrow decreasing. Note escrow drain only applies to a fixed-deposit payer (e.g. a
  consumer/gateway that deposits once), which is not the local-network DIPs setup.

## 12. D-6.1 first-collection `maxInitialTokens` bonus is unobservable — local agreements use `maxInitialTokens = 0` — confirmed

- **Doc:** D-6.1 — "The first collection includes `maxInitialTokens`, a one-time amount added
  only when `lastCollectionAt == 0` … confirm the first is larger by roughly `maxInitialTokens`."
- **Reality:** dipper's RCA terms on local-network carry `max_initial_tokens = 0x0`, so there
  is no bonus to observe; the first collection is just `collectionSeconds × rate` like the
  rest. D-6.1 cannot be positively demonstrated without configuring a non-zero
  `maxInitialTokens` in dipper's offer.
- **Fix.** Either note D-6.1 is N/A when `maxInitialTokens = 0` (local default), or have dipper
  offer a non-zero `maxInitialTokens` for this test.

## 13. E-3 "both proposals accepted, sharing one allocation" is impossible — contract enforces one agreement per allocation — confirmed

- **Doc:** `LocalNetworkTestPlan.md` E-3 pass criteria — "On the next tick the deferred proposal
  is accepted against the now-existing allocation (the D-3.1 reuse path) — both end `accepted`,
  sharing one allocation."
- **Reality:** the allocation id is deterministic per (indexer, deployment), so two proposals
  for the same deployment target the **same** allocation, and the on-chain `SubgraphService`
  enforces **one indexing agreement per allocation**. After the first proposal is accepted
  (creating the allocation + agreement), accepting the second reverts
  `AllocationAlreadyHasIndexingAgreement(allocationId)` (selector `0x333e316d`). Verified by
  injecting two same-deployment proposals: A accepted, B deferred one tick (dedup works), then B
  **rejected** with that contract error. "Both accepted sharing one allocation" cannot happen.
- **Fix.** Reword E-3: the *dedup* behavior (accept one per deployment per tick to avoid racing
  the deterministic allocation id) is the real thing under test and it works; the correct final
  outcome is **one accepted, the other rejected** (`AllocationAlreadyHasIndexingAgreement`), not
  both accepted. Optionally note the agent could reject the duplicate off-chain before the
  guaranteed on-chain revert (minor efficiency; end state is already correct).

## 14. N-6 stale-subgraph (lag) scenario is not reproducible on local-network — staleness is wall-clock based vs a time-traveling chain — confirmed

- **Doc:** `LocalNetworkTestPlan.md` N-6 — "Pause the indexing-payments subgraph … and let it
  fall more than 5 minutes behind chain head" → agent skips the reaper.
- **Reality:** the agent's staleness guard (`dips.ts`) computes
  `lagSeconds = Math.floor(Date.now()/1000) - subgraphHeadBlockTimestamp` and skips the reaper
  when `lagSeconds > 300` **or** the read is `null`. On local-network the chain time-travels
  forward via `anvil_mine`, so the chain's block timestamps run **ahead of real wall-clock**
  (measured: chain ~2880s ahead). Thus `lagSeconds` is **negative** and the lag branch never
  fires — pausing the subgraph + advancing chain time makes it *less* stale, not more. Collection
  continues regardless (reads on-chain), which was verified. Only the `null` (unreadable) branch
  is triggerable locally, and only by making the subgraph query fail (remove/break it —
  disruptive).
- **Fix.** Either (a) note in N-6 that the lag scenario is not reproducible on a time-traveling
  local chain and test the guard via the *unreadable* branch instead (make the indexing-payments
  subgraph query fail); or (b) upstream, consider measuring lag against chain head timestamp
  rather than `Date.now()` so the check behaves on non-real-time chains. On a live network the
  two agree, so this is primarily a local-testing limitation.

## 15. N-4 and N-5 aren't suitable for a repeatable local-network integration suite (destructive / infeasible) — confirmed

- **Doc:** `LocalNetworkTestPlan.md` lists N-4 (escrow underfunded) and N-5 (missing provision)
  as negative checks.
- **Reality:**
  - **N-4** — the DIPs payer is the `RecurringAgreementManager` and its escrow is topped up by
    issuance before every collect (protocol-funded). There is no non-destructive way to bring
    escrow below the amount owed (would require disabling issuance), so
    `PaymentsEscrowInsufficientBalance` can't be provoked here.
  - **N-5** — the revert requires `getProviderTokensAvailable(indexer, SubgraphService) == 0`,
    i.e. thawing the indexer's entire provision (large, 2h thaw period). That risks the agent
    auto-closing every allocation and forces a full stack reset — it destroys all other state.
- **Fix.** Mark N-4/N-5 as **not part of the repeatable local-network suite** (their mechanisms
  are verifiable from source or via contract unit tests). If they must be exercised, do them on
  a throwaway single-agreement stack as the *last* action before a reset, or cover them with
  Foundry unit tests against `RecurringCollector`/`PaymentsEscrow` rather than the full stack.

---

_Add entries as we go. Each: doc file + location, what it says, what actually happens, the fix._
