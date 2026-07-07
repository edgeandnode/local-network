# DIPs Local Testing - Bug Tracker

Open bugs only. A fixed bug is pruned once its fix — and the why behind any non-obvious
guard — lives at the call site in the tree; git history and the PRs carry the forensics.
Pruned 2026-07-07: BUG-001 through 006, 009, 010 (see this file's prior revisions).

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
