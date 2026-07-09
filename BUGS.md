# DIPs Local Testing - Bug Tracker

Open bugs only. A fixed bug is pruned once its fix — and the why behind any non-obvious
guard — lives at the call site in the tree; git history and the PRs carry the forensics.

Clean slate as of 2026-07-08. The 2 remaining entries were pruned with their fixes merged:
the burst-scale bug (dipper #661 offer pacing and #662 queue priority — a burst now queues
instead of expiring) and the stranded-allocations bug (the pinned indexer-agent's rule
reaper with its subgraph staleness guard, graphprotocol/indexer #1221/#1224/#1225/#1227).
Pruned 2026-07-09: the test-abort bug (aborted allocation tests left the stack broken for
every later test) landed as local-network #83, which restores allocation state on any
failure and gives the DIPs tests a fail-fast warm-up. Prior entries live in this file's
history.

## Bug 1: indexer-agent reconciliation races operator allocation changes, then blocklists the deployment

**Symptom.** The first mirror CI run on the paced dipper pin (sha-cb89726, run 28872292749)
failed 3 tests. `close_and_recreate_allocation` recreated its allocation, and roughly 15
seconds later its own close attempt failed with "Allocation has already been closed" —
something else had closed the fresh allocation on-chain. Both DIPs lifecycle tests then
timed out with 0 agreements; the agent log shows why: "Blocklisted deployment 0x5655f0cb...,
rejecting proposal c14105eb..." — that hex is the graph-network deployment the tests target.

**Root cause.** 2 compounding defects in the indexer-agent. First, a reconcile pass mixes
snapshots from different moments: allocation decisions come from an earlier rules read, but
`reconcileActions` deliberately re-fetches active allocations fresh (agent.ts:1265-1269,
"Accuracy check"), so a don't-allocate decision computed while the rule briefly said
`offchain` (stamped by the management API's closeAllocation) was executed against the
allocation the test had since recreated under an `always` rule. Second, `confirmUnallocate`
(indexer-common allocations.ts:918-925) unconditionally stamps a `never` rule after any
agent-driven close, overwriting the operator's `always` rule. `never`/`offchain` rules
blocklist the deployment for DIPs (`isOnChainOptOutRule`, dips.ts:1176), so the one proposal
dipper sent was rejected 3 seconds after delivery. Dipper's own behaviour was correct
throughout: proposal created, chain-time expiry at the 600-second deadline, reassessment
queued (IISA then returned 0 candidates because the deployment had no serving allocation).

**Owning repo.** graphprotocol/indexer.

**Fix.** Re-validate the rule when an unallocate action executes (skip if the current rule
says `always`/`dips`), and make `confirmUnallocate` stamp `never` only when the rule that
justified the close is still in place — not clobber a rule the operator changed since the
decision was queued.

**PR.** graphprotocol/indexer #1242 and #1243 (open, CI green), plus #1244 stacked on
#1242, which cancels a stale queued close at execution time and lets deliberate closes
stick.

## Bug 3: dipper offers collection terms the contract rejects, then retries the revert forever

**Symptom.** With `min_seconds_per_collection: 60, max_seconds_per_collection: 240` in dipper's
config, every offer submission reverted (selector `0xe4576396`,
`RecurringCollectorAgreementInvalidCollectionWindow`) and dipper logged "Failed to submit offer
on-chain, will retry" in a loop. Indexers had accepted the proposals off-chain and sat waiting
for an on-chain offer that never landed; all 3 proposals burned their full 600-second deadline,
expired, and dipper reassigned to 3 more indexers whose offers reverted identically.

**Root cause.** The RecurringCollector requires `max - min >= MIN_SECONDS_COLLECTION_WINDOW`
(600, a contract constant). Dipper neither validates its configured window against that bound
(at startup or before offering) nor decodes the custom-error revert — so an invalid config
produces an unbounded revert-retry loop and silently wasted proposal deadlines instead of a
clear failure.

**Owning repo.** edgeandnode/dipper.

**Fix.** Validate the collection window at config load (fail fast naming the contract bound),
decode known RecurringCollector custom errors in the submit-offer path, and treat a
deterministic revert as terminal for that agreement rather than retrying it indefinitely.

**PR.** edgeandnode/dipper #664 (startup validation of the window and its sibling duration
bounds) and #665 (decode the revert, fail the job, let expiry reassign), both open and CI
green.
