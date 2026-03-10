# DIPs Testing Status

Tracking what has and hasn't been tested end-to-end in local-network before testnet deployment.

## What works

### 1. Proposal happy path

1. Dipper receives an indexing request via admin RPC (`indexings register`)
2. IISA scores available indexers and returns candidates (single indexer in local-network)
3. Dipper constructs a RecurringCollectionAgreement, signs it via EIP-712, and sends the proposal to indexer-service over gRPC
4. Indexer-service validates the proposal (signature, pricing, network, deadline) and accepts
5. The signed RCA is stored in `pending_rca_proposals` with status `pending`
6. The indexer-agent consumer (PR #1174) picks up the proposal and checks whether an indexing rule exists for the deployment

### 2. Supporting infrastructure

TAP subgraph correctly points at Horizon PaymentsEscrow, signer authorization events are indexed, gateway queries return 200, RecurringCollector address is written to horizon.json.

### 3. Indexer-service rejection paths

Five of the eight rejection paths have been tested end-to-end.

**PriceTooLow**: Temporarily set `min_grt_per_30_days["hardhat"] = "999999"` in indexer-service config. Dipper's pricing (`174000000000000` wei/s, ~450 GRT/30d) fell below the inflated minimum. Indexer-service rejected with `PRICE_TOO_LOW`, dipper recorded it correctly. The indexer enters a 1-day lookback exclusion for that deployment.

**UnsupportedNetwork**: Set `supported_networks = []` in indexer-service config. The deployment's network (`hardhat`, resolved from the IPFS manifest) had no matching entry. Indexer-service rejected with `UNSUPPORTED_NETWORK`, dipper recorded it correctly. The indexer enters a 30-day lookback exclusion.

**SubgraphManifestUnavailable**: Sent a request for a non-existent deployment ID (`QmWmyoMoctfbAaiEs2G46gpeUmhqFRDW6KWo64y5r581Vz`). The indexer-service attempted to fetch the manifest from IPFS (190-second timeout), failed, and rejected with `SUBGRAPH_MANIFEST_UNAVAILABLE`. Dipper recorded it correctly. The indexer enters a 5-minute lookback exclusion.

**DeadlineExpired**: Set `deadline_seconds: 0` in dipper config and added 2-second network delay on the indexer-service gRPC port using `tc netem`. The delay is necessary because the local pipeline delivers proposals in under 6ms -- well within the same second -- so without it, the second-precision deadline check (`deadline < now`) always passes. With the delay, the indexer-service received the proposal 2 seconds after dipper computed the deadline, and rejected with `DEADLINE_EXPIRED` (`agreement deadline 1772672762 has already passed (current time: 1772672764)`). Dipper recorded the rejection correctly. The technique requires `NET_ADMIN` capability on the indexer-service container and `iproute2` installed. Port-specific delay (`tc filter` on port 7602) avoids disrupting the rest of the indexer-service's network traffic.

**SignerNotAuthorised**: Changed dipper's DIPs signer key to an arbitrary unauthorized key (`0x0123...`, address `0xFCAd0B19bB29D4674531d6f115237E16AfCE377c`) while leaving the TAP signer unchanged. The indexer-service checked the recovered signer against the RecurringCollector's authorized signers, found no match, and rejected with `SIGNER_NOT_AUTHORISED`. Dipper recorded the rejection correctly. Previously blocked by the topology crash-on-restart bug (dipper PR #578), which has since been fixed.

### 4. Dipper status and listing commands

All CLI read commands work correctly. `indexings list` returns all requests with correct metadata. `indexings status` accepts both UUIDs and deployment IDs, returning 404 for unknown UUIDs. `agreements list` returns agreements per request, with an empty array when none exist. A duplicate request for the same deployment+indexer correctly fails with a unique constraint (`idx_unique_active_agreement_per_indexer_deployment`) -- the request is created but no duplicate agreement is added.

### 5. Multiple requests and concurrent proposals

A second request for the same deployment (`QmPdb`) was accepted -- dipper does not deduplicate requests. However, the `idx_unique_active_agreement_per_indexer_deployment` constraint prevented a duplicate agreement for the same indexer+deployment. The second request sat in OPEN with zero agreements. The constraint violation is now handled gracefully (dipper PR #579) -- the handler logs a warning and skips the candidate instead of failing the job.

Requests for different deployments worked independently. All three local-network deployments received separate requests and agreements without interference.

Multiple agreements for the same indexer worked as expected. With a single indexer in local-network, every agreement targets `0xf4EF...`. Three concurrent agreements (one per deployment) coexisted without issues.

### 6. Cancellation flows

**Request cancellation** (`indexings cancel`): Cancelling an OPEN request transitions it to `CANCELED` and cascades to all active agreements, marking them `CANCELED_BY_REQUESTER`. Cancelling an already-cancelled request is idempotent (no error). Cancelling a non-existent request returns 404.

**Agreement cancellation** (`agreements cancel`): Cancelling a specific `CREATED` agreement marks it `CANCELED_BY_REQUESTER` and immediately triggers reassessment. IISA returns new candidates, and dipper creates a replacement agreement for the same request. In local-network with one indexer, the replacement agreement targets the same indexer -- the unique constraint allows it because the original agreement is no longer active. Cancelling the parent request after agreement cancellation cascades to both the original and the reassessment-created agreement.

### 7. Agreement expiration and reassessment

Enabled the expiration service (`interval: 10s, batch_size: 100`) and set `deadline_seconds: 5` to create agreements that expire quickly. The proposal was accepted by the indexer within milliseconds (pipeline completes in <6ms). Seven seconds after creation, the expiration service found the agreement past its deadline, marked it `Expired`, and queued a reassessment job. The reassessment handler ran but determined "no changes needed" -- the only candidate was the same indexer that already had the expired agreement. No replacement agreement was created, leaving the request in OPEN with one expired agreement. This is correct for a single-indexer environment; with multiple indexers, reassessment would find alternative candidates.

## Indexer-agent

PR #1174 (`feat/dips-pending-rca-consumer`) adds the migration and consumer that reads `pending_rca_proposals` and creates indexing rules. PR #1175 (`feat/dips-on-chain-accept`, targeting #1174) adds `acceptPendingProposals()` which calls `acceptIndexingAgreement` on SubgraphService on-chain. If no allocation exists for the deployment, it atomically creates one via `multicall(startService + acceptIndexingAgreement)`. The local-network indexer-agent now runs on `feat/dips-on-chain-accept`.

### Payment collection

The `DipsCollector` still operates on the old `IndexingAgreement` model, not `pending_rca_proposals`. The full collection flow (agent calls dipper's `CollectPayment` RPC, dipper calls `collect()` on RecurringCollector on-chain, funds move from payer's escrow to the indexer) can't be exercised until the collector is updated to work with the new table.

### RecurringCollector contract operations

The contract has several functions beyond `accept()` that are part of the full lifecycle: `collect()` (payment collection), `update()` (update agreement terms), `cancel()` (on-chain cancellation by either party), and collection window enforcement (`minSecondsPerCollection` / `maxSecondsPerCollection` validation during collect). Collection cannot be tested until the collector is updated.

## What hasn't been tested

### #1 Indexer-service rejection paths (remaining)

Five of eight rejection paths were tested end-to-end (see "What works" section 3). The remaining three are defensive guards against malformed or misrouted traffic that correct clients cannot produce. All three are covered by unit tests in indexer-rs (`test_validate_and_create_rca_wrong_service_provider`, `test_validate_and_create_rca_malformed_abi`, `test_validate_and_create_rca_invalid_metadata_version`). E2E testing is not warranted.

- **UnexpectedServiceProvider** -- guards against misrouted proposals. Correct clients always set the right `service_provider` from network topology.
- **InvalidSignature** -- catches corrupted or truncated signature bytes. No correct client produces these.
- **UnsupportedMetadataVersion** -- catches future protocol versions. Dipper always sends version 1.

### #2 Dipper lifecycle beyond proposal delivery

Most lifecycle paths have been tested (see "What works" sections 6 and 7). Remaining:

- **On-chain cancellation of rejected agreements**: If an agreement was rejected off-chain but somehow accepted on-chain, dipper calls `cancelIndexingAgreementByPayer` on SubgraphService to prevent payment. Edge case, untested and blocked on indexer-agent on-chain acceptance support.

### #3 Restart resilience

Dipper was killed (`docker kill`) after processing a request and restarted. All state survived -- requests, agreements, and metadata were fully preserved in Postgres. Dipper has no in-memory state recovery mechanism; it reconnects to the database, runs migrations (idempotent), and resumes. The expiration service catches any `Created` agreements that expire while dipper is down.

The pipeline completes so fast (<6ms from request registration to indexer acceptance) that simulating a crash between request registration and IISA candidate selection is impractical in local-network. If dipper crashes mid-pipeline, the request sits in `OPEN` with no agreements. There is no explicit recovery for in-flight jobs -- the request would need manual reassessment or a new request.

Untested scenarios that depend on indexer-agent changes:
- Indexer-agent restarts mid-reconciliation while processing pending proposals (blocked on PR #1174)
- Indexer-service accepts a proposal but crashes before writing to `pending_rca_proposals` (out-of-sync risk between dipper and indexer)

### #4 Gateway awareness of DIPs

The gateway has no DIPs-specific code. It routes queries to indexers via TAP regardless of whether a DIPs agreement exists. This is expected (DIPs is a payment mechanism, not a query routing mechanism), but it means there's no way to verify from the gateway side that a DIPs-funded query is being served correctly. The indexer just indexes and serves -- payment happens separately.

### #5 IISA scoring cronjob — degraded mode only

The `iisa-cronjob` container runs the real IISA scoring pipeline from the IISA repo (`cronjobs/compute_scores/`). Without GeoIP databases (no MaxMind license key in local-network) and with minimal Redpanda data, the full pipeline (latency regression, geographic distance, iterative filtering) cannot run. The cronjob falls back to degraded mode: it discovers indexers from the network subgraph, fetches `/dips/info` from each indexer-service to collect real pricing data, and writes scores with equal quality metrics. All indexers get identical latency/uptime/success scores (0.5) but carry their actual `min_grt_per_30_days` and `supported_networks` from `/dips/info`.

This enables the per-indexer pricing path through IISA and dipper. What remains untested is the full scoring pipeline's differentiation between indexers — latency regression, GeoIP-based distance calculation, and stake-to-fees ratios. These require production-scale Redpanda data and MaxMind GeoIP databases.

**Verification (not yet done — requires fresh deploy):**

1. Fresh deploy (`down -v`, `up -d --build`)
2. Cronjob container starts, fails the full pipeline (no GeoIP, minimal data), degrades to equal-score mode
3. Cronjob fetches `/dips/info` from indexer-service, writes scores file with `dips_info_available: true` and real `dips_min_grt_per_30_days` values
4. IISA loads scores — verify pricing is populated
5. Send indexing request via dipper CLI
6. Check dipper logs: `iisa_price=true` in "Creating agreement with pricing" log (confirms IISA pricing used, not static fallback)
7. Indexer-service accepts the proposal

### #6 Scale to 10+ indexer network

Local-network runs one indexer, so IISA candidate selection is trivial (always picks the only option). Multi-indexer scoring, tiebreaking, and reassignment to a different indexer after rejection can't be tested without scaling up. A full indexer stack (graph-node ~68MB, postgres ~200MB, indexer-agent ~300MB, indexer-service ~45MB) is roughly 600MB per indexer. On a 64GB machine, 10 full indexer stacks would use around 6GB -- well within budget. This would give us a realistic local network where different indexers index different subgraphs, IISA selects from a real candidate pool, and dipper delivers proposals to genuinely independent indexers.

## Testing environment limitations

**Instant finality**: Anvil mines blocks with `--block-time 1` (dev override) or `--block-time 30` (default) with no reorg risk. Timing-sensitive flows like collection window enforcement behave differently than on a real chain. Deadline expiry testing required artificial network delay (`tc netem`) because the local pipeline completes in under 6ms.

**No real escrow funding**: The payer (ACCOUNT0) has unlimited hardhat ETH/GRT. Escrow balance checks, insufficient funds scenarios, and deposit flows aren't meaningfully tested.

**Degraded IISA scoring**: The iisa-cronjob runs in degraded mode (no GeoIP, minimal Redpanda data) and assigns equal quality metrics to all indexers. Real per-indexer pricing is fetched from `/dips/info`, but quality differentiation between indexers is not available. See item #5.

## Issues we encountered

### Dipper topology crash on restart (fixed)

Dipper's initial topology fetch used `?` to propagate errors, which crashed the process if the gateway was temporarily unavailable. After the chain went idle (no new blocks), the gateway returned 402, causing dipper to crash-loop on every restart. Fixed in dipper PR #578 -- the initial fetch now retries with indefinite exponential backoff (capped at 32 seconds).

### Chain staleness causing gateway 402s (fixed)

Anvil in automine mode only produced blocks on transaction submission. Once the chain went idle, the gateway considered the network subgraph stale and returned 402 for all queries. Fixed by adding `--block-time` to the chain's `run.sh`, which mines blocks periodically regardless of transaction activity. The dev compose override sets `BLOCK_TIME=1` for fast Ignition deploys; the default is 30 seconds.

### UnexpectedServiceProvider not testable via pipeline

Changing `indexer_address` in indexer-service config breaks query serving entirely (the indexer can't find its allocations), so IISA never finds candidates. This is expected behaviour -- the validation exists to catch misrouted proposals, not misconfigured indexers. Testing this path requires a raw gRPC call bypassing dipper's pipeline.

### Indexer-service rejection logging

Indexer-service previously logged rejections at WARN level without the deployment ID. Fixed in indexer-rs PR #968 -- rejections are now logged at INFO level with the deployment ID and specific rejection reason.
