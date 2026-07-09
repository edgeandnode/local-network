# DIPs Local Testing - Bug Tracker

Open (not merged) bugs only.

## Bug 1: indexer-agent reconciliation races operator allocation changes, then blocklists the deployment

**PR.** graphprotocol/indexer #1242 and #1243 (open, CI green), plus #1244 stacked on
#1242, which cancels a stale queued close at execution time and lets deliberate closes
stick.

## Bug 3: dipper offers collection terms the contract rejects, then retries the revert forever

**PR.** edgeandnode/dipper #664 (startup validation of the window and its sibling duration
bounds) and #665 (decode the revert, fail the job, let expiry reassign), both open and CI
green.
