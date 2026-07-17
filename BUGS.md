# DIPs Local Testing - Bug Tracker

Open (not merged) bugs only.

## Bug 7: dipper pushes a SIGNED RCA proposal; indexer-agent expects an unsigned one and rejects every proposal (`non_empty_signature`)

**Symptom.** DIPs happy path is fully blocked at D-2/D-3. Origination succeeds (dipper
returns a request id; IISA selects the indexer; indexer-service logs `RCA accepted` at the
gRPC layer and queues a `pending_rca_proposals` row), but ~4s later the agent flips the row
to `rejected` and no on-chain offer is ever posted. The dipper agreement stays `status=-1`
(CREATED); the indexing-payments subgraph never gets an `Offer`. Agent log:

```
level 50: Pending RCA proposal <id> has non-empty signature (producer regression); rejecting  signatureLength=65
level 30: Rejected proposal <id>: non_empty_signature
```

**Root cause.** Producer/consumer protocol skew. The indexer-agent's pending-RCA consumer
(`indexer-common/dist/indexing-fees/pending-rca-consumer.js`, `decodeRow`) requires the
pushed proposal's signature to be **empty** (`0x`/absent) — the design is that dipper pushes
an *unsigned* RCA and the agent handles on-chain acceptance; a non-empty signature is treated
as a "producer regression" and hard-rejected. But dipper `sha-cb89726` (main) signs the RCA
(65-byte sig) before pushing. The two pinned/running versions disagree on whether the pushed
proposal carries a signature, so every proposal dies at the agent boundary.

Versions: indexer-agent = `local` build (pkg 0.25.10, has the guard; `.env.local` overrides
the pinned `sha-8ed8fb8` / PR #1238 main-dips); dipper = `DIPPER_VERSION=sha-cb89726` (main).

**Actual root cause (resolved): local-network runs a STALE indexer-agent build that predates
the reconciliation PR.** The signature question was already settled across the two repos:

- **dipper (main, incl. pinned `cb89726`):** deliberately *signs* the gRPC proposal so the
  indexer can recover/authenticate the sender (dipper PR **#626**;
  `indexer_rpc_client.rs::build_proposal_request` "Always sign the gRPC proposal…"). This is
  intended and stays.
- **indexer (`main-dips`, current tip `aefddf61`, 2026-07-11):** *ignores* the signature.
  PR **#1241** "fix: ignore a stored RCA signature instead of rejecting it" (merged
  2026-07-09) changed the consumer from reject→ignore:
  `pending-rca-consumer.ts` → "An embedded signer signature is **ignored** — acceptance is
  offer-based, so the agent has no use for it." (`const { rca } = signedRca` — signature not
  read.) Current `origin/main-dips` contains this.

So the contract is coherent now: **dipper signs, agent ignores the signature, acceptance is
offer-based.** The only reason local saw `non_empty_signature` rejection is that the running
agent image (`ghcr.io/graphprotocol/indexer-agent:local`, built 2026-06-12) predates #1241
and still has the old reject guard. The pinned `sha-8ed8fb8` (#1240) may also predate #1241.

**Repo / fix (local-network config).** Run/pin an indexer-agent that includes #1241 (current
`main-dips`, `aefddf61` or later). Either bump `INDEXER_AGENT_VERSION` to a published image
tag ≥ #1241, or run current `main-dips` from source via the `compose/dev/indexer-agent.yaml`
override (INDEXER_AGENT_SOURCE_ROOT). No upstream code fix needed — the upstream repos already
agree.

**PR.** none needed upstream. local-network action only: advance the pinned/ran indexer-agent
past #1241 (the pinned `sha-8ed8fb8` and the `local` image are stale). Consider bumping the
`.env` pin once a suitable image tag is confirmed.

**Verified fixed.** Ran current `main-dips` (`aefddf61`, includes #1241) from source via the
`compose/dev/indexer-agent.yaml` override. A fresh origination was accepted end-to-end:
proposal `completed` (signature ignored, no `non_empty_signature`), dipper agreement
`AcceptedOnChain` (6), new allocation opened via multicall (D-2/D-3.2 pass).

## Bug 8: dev override `run-override.sh` is stale — missing all DIPs agent config → agent crashes on startup

**Symptom.** Running indexer-agent from source via `compose/dev/indexer-agent.yaml`
(INDEXER_AGENT_SOURCE_ROOT), the agent crashes during network setup:
`TypeError: Cannot read properties of undefined (reading 'status')` at
`indexer-common/src/subgraph-client.ts:156` (from `network.ts:168`, creating the
IndexingPayments subgraph client). The management API (7600) never comes up.

**Root cause.** `containers/indexer/indexer-agent/dev/run-override.sh` predates the DIPs work
in the normal `containers/indexer/indexer-agent/run.sh`. It omits
`INDEXER_AGENT_INDEXING_PAYMENTS_SUBGRAPH_ENDPOINT` (so the agent builds an IndexingPayments
subgraph client with neither endpoint nor deployment → `deploymentInfo!.status` on undefined),
plus `INDEXER_AGENT_TAP_SUBGRAPH_ENDPOINT`, `INDEXER_AGENT_TAP_ADDRESS_BOOK`, and the entire
DIPs enablement block (`ENABLE_DIPS`, `DIPS_*`, `DIPPER_ENDPOINT`, `OFFCHAIN_SUBGRAPHS` pin).
Without those, even if it started it would never run the DIPs accept path.

**Repo / fix (local-network).** Ported the missing config from `run.sh` into
`run-override.sh` (indexing-payments + tap subgraph endpoints, tap address book, and the
`recurring_collector`-gated DIPs block). Agent then boots and enables DIPs. Longer term the
override should source/share the config with `run.sh` so they don't drift again.

**PR.** committed to local-network (this repo) — the `run-override.sh` edit.

## Bug 9: `start-indexing` image ships indexer-cli 0.23.8 — incompatible with the Horizon/main-dips agent close path → forced closes fail (IE070)

**Symptom.** `graph-indexer indexer allocations close <net> <id> <poi> --force` (from the
`start-indexing` image) against the main-dips agent fails with
`[GraphQL] Failed to query latest valid epoch and block hash` (IE070). Agent logs show
`blockHashFromNumber(networkAlias="hardhat", blockNumber=null)` →
`Invalid value provided for argument "blockNumber": Null`, retried 5× then IE070.

**Root cause.** Version mismatch. The image's indexer-cli is **0.23.8**, whose `close`
signature is `close <network> <id> <poi>` — no block number. The main-dips **agent** (0.25.10)
close path (`monitor.ts::_resolvePublicPOI`) needs a Horizon `blockNumber` (+ `publicPOI`) to
resolve the POI block hash; with `--force` it short-circuits only when `publicPOI !==
undefined`, else it calls `blockHashFromNumber(alias, blockNumber)` with `blockNumber=null`.
The matching CLI (0.25.10, in the indexer source) has
`close <id> <poi> <blockNumber> <publicPOI> --network <net>` — the Horizon-aware form.
This blocks any forced close via the shipped CLI: D-7.3 (force-close), D-8.3 (opt-out close),
and post-test allocation cleanup.

**Repo / fix (local-network).** Bump the indexer-cli in `containers/indexer/start-indexing`
(and anywhere the CLI image is used) to a version matching the agent (≥0.25.x, Horizon
close args). Interim: run the CLI from the main-dips source (packages/indexer-cli) with the
`<blockNumber> <publicPOI>` args, or drive the close via the management API with those fields.

**PR.** none yet — local-network image/pin bump.

**D-7 note.** D-7.1 (non-forced close rejected by the DIPs guard) and D-7.2 (allocation not
auto-closed) PASS. D-7.3 (force-close cancels agreement → state 2) is blocked by this CLI
mismatch, not by DIPs logic — the DIPs `assertSafeToCloseAllocation` force path works; the
failure is the generic Horizon POI-block resolution.

**Secondary observation (not yet exercised).** The rejected proposal's `terms` carried
`conditions: 2`, but CLAUDE.md notes local-network should always use `conditions = 0`
(non-zero makes RecurringCollector staticcall the payer for an eligibility callback). This
never got exercised because the signature check rejects first; revisit once Bug 7 is resolved.

## Bug 1: indexer-agent reconciliation races operator allocation changes, then blocklists the deployment

**PR.** graphprotocol/indexer #1242 and #1243 (open, CI green), plus #1244 stacked on
#1242, which cancels a stale queued close at execution time and lets deliberate closes
stick.

## Bug 3: dipper offers collection terms the contract rejects, then retries the revert forever

**PR.** edgeandnode/dipper #664 (startup validation of the window and its sibling duration
bounds) and #665 (decode the revert, fail the job, let expiry reassign), both open and CI
green.

## Bug 4: `just reset` silently leaves `config-local` (stale contract addresses) → Phase 3 aborts

**Symptom.** After `just reset && just up`, `graph-contracts` exits 1 in Phase 3 with
`Sync failed for <Contract>: no code on-chain` (e.g. RewardsManager_Implementation, or
IssuanceAllocator "stale (no code)"). Phase 1/2 succeed; the whole DIPs/issuance deploy
aborts and every downstream service stays `Created`.

**Root cause.** `just reset` (`docker compose down -v`) only tears down services in the
*active* `COMPOSE_PROFILES`. A container from a **disabled** profile that is still running
(here `eligibility-oracle-node`, `rewards-eligibility` profile) keeps `config-local`
mounted, so `down -v` cannot remove that volume. Chain state (`chain-data`, used only by
the active `chain` service) *is* wiped, so the next `up` deploys a fresh chain — but the
persisted `config-local` still holds the previous deploy's address book. Phase 3's
`syncComponentsFromRegistry` reads those stale addresses, finds no code at them on the
fresh chain, and hard-fails (unlike Phase 1, which self-heals via a direct `cast code`
check). Confirmed: `config-local` `CreatedAt` stayed weeks old while `chain-data` was
recreated fresh.

**Repo / fix (local-network).** Make `reset`/`down` tear down *all* profiles so stray
containers can't pin volumes — e.g. run the recipe with `COMPOSE_PROFILES` set to every
profile (or `docker compose --profile "*" down -v`). Optionally have Phase 3's sync
fall back to redeploy when the recorded address has no code, matching Phase 1. Immediate
unblock: `docker rm -f` the stray container, then `docker compose down -v` (it can now
remove `config-local`), then `just up`.

**PR.** none yet.

## Bug 5: escrow-manager's one-shot gateway-signer authorization is lost on a transient tx timeout → all paid queries 402, dipper never bootstraps

**Symptom.** Fresh deploy comes up but `dipper` stays `unhealthy`, looping
`initial topology fetch failed ... failed to fetch subgraphs info`. The gateway returns
`bad indexers: {0xf4ef…: BadResponse(402)}`; the indexer's 402 body is
`No sender found for signer 0x70997970C51812dc3A010C7d01b50e0d17dc79C8` (the gateway's TAP
receipt signer, ACCOUNT1). Network is fully synced and allocated, so it is purely the TAP
query-payment authorization.

**Root cause.** `graph-tally-escrow-manager` authorizes its signers once at startup,
signing from `ACCOUNT0_SECRET` — the same deployer account under heavy load during the
startup window. The `authorizeSigner` tx for the gateway signer (ACCOUNT1) timed out
(`transaction was not confirmed within the timeout`) and was **never retried**; the
process fell through to its steady-state receipt/RAV loop with the gateway signer still
unauthorized. Indexer-service therefore can't map the signer to any sender and rejects
every gateway query with 402, so dipper can never fetch topology. Restarting
`graph-tally-escrow-manager` re-runs the authorization (now uncontended) and both signers
go `authorized=true`; the 402 clears and dipper reaches `healthy` immediately.

**Repo / fix.** Upstream `graph_tally_escrow_manager`: retry failed signer authorizations
in the update loop instead of one-shot at startup. local-network: order
`graph-tally-escrow-manager` to start after the deployer is quiescent (it currently
`depends_on start-indexing:service_completed_successfully`, which is not enough), and/or
give it a signer secret distinct from the deployer to remove the nonce race. Immediate
unblock: `docker compose restart graph-tally-escrow-manager`.

**PR.** none yet.

## Bug 6: Phase 3 deploy is not idempotent on a warm resume — RewardsManager left mid-upgrade breaks re-runs

**Symptom.** A *fresh* `just reset && just up` deploys cleanly (Phase 3 completes, stack
healthy). But `just up` (or `just up --build`) on **preserved volumes** — chain state and
`config-local` fully consistent, Phase 1/2 idempotently SKIP, first Phase 3 stage re-syncs
"44 contracts synced" — then fails in `GIP-0088:upgrade,configure`:
`AbiFunctionNotFoundError: Function "GOVERNOR_ROLE" not found on ABI` at
`packages/deployment/deploy/rewards/reclaim/04_configure.ts:56` (ReclaimedRewards
configure). `graph-contracts` exits 1 and downstream services stay `Created`.

**Root cause.** Phase 1/Phase 3 leave RewardsManager half-upgraded: the proxy points at
the live implementation (`0x9A9f…`) while the deploy records a **pending upgrade** to a
newer implementation (`0x5c74…`, which does define `GOVERNOR_ROLE`). On a single-pass
fresh deploy this never bites. On a resume, rocketh reloads the pending-upgrade record and
`04_configure`'s `extraDependencies` encodes `GOVERNOR_ROLE()` against the *old* impl's ABI
(no such function) and throws client-side before any chain call. Same dangling
RewardsManager pending implementation that also produced Bug 4's "no code on-chain" sync
failure when the chain was fresh — the common defect is that the deploy never applies (or
never clears) the pending RewardsManager upgrade, so Phase 3 is non-idempotent.

**Repo / fix (contracts / graph-contracts run.sh).** Drive the RewardsManager upgrade to
completion (apply the pending impl and clear the pending record) so a re-run sees a settled
state, or make the reclaim/configure scripts tolerate a pending upgrade (resolve the ABI
from the pending impl, or skip when already configured) instead of throwing. Until then,
the resume path is unreliable — always redeploy clean. Immediate unblock:
`just reset && just up` (a clean single pass; `reset` now actually wipes `config-local`
since the volume-pinning stray containers from Bug 4 are gone).

**PR.** none yet.
