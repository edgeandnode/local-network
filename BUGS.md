# DIPs Local Testing - Bug Tracker

Open bugs only. A fixed bug is pruned once its fix — and the why behind any non-obvious
guard — lives at the call site in the tree; git history and the PRs carry the forensics.

Clean slate as of 2026-07-08. The 2 remaining entries were pruned with their fixes merged:
the burst-scale bug (dipper #661 offer pacing and #662 queue priority — a burst now queues
instead of expiring) and the stranded-allocations bug (the pinned indexer-agent's rule
reaper with its subgraph staleness guard, graphprotocol/indexer #1221/#1224/#1225/#1227).
Prior entries live in this file's history.

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

**PR.** Not yet submitted.

## Bug 2: allocation test aborts leave the stack broken for every later test

**Symptom.** Same run: after `close_and_recreate_allocation` aborted mid-flow, nothing
restored the graph-network allocation or cleared the opt-out rule. The gateway refused all
queries for the deployment ("subgraph not found: no allocations", first at 14:19:19, 12
seconds after the abort, then every 60 seconds until teardown), dipper's topology refresh
failed for the rest of the run, and both DIPs tests failed as collateral.

**Root cause.** The test restores state (recreate allocation, which also resets the rule to
`always`) only on its success path; an error at any close step skips the restore. Later
tests assume an active allocation exists and don't re-establish it.

**Owning repo.** local-network (test suite on the mirror branch and the upstream PR #67 port).

**Fix.** Restore state in a failure-tolerant guard so an aborted run still ends with an
active allocation and an `always` rule, and make the DIPs tests' warm-up ensure an active
allocation instead of assuming one. This is test independence, not a mask: Bug 1 stays
open against the agent regardless.

**PR.** Not yet submitted.

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

**PR.** Not yet submitted.
