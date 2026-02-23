# Rewards Eligibility Oracle - Status

> Last updated: 2026-02-18

## Current Phase: End-to-end verified

### Summary

REO is fully integrated into the local network. Both workstreams complete and end-to-end flow verified:

1. **Contract deployment** - DONE: Phase 4 deploys REO, integrates with RewardsManager, grants ORACLE_ROLE
2. **REO node** - DONE: consumes gateway_queries, evaluates eligibility, submits on-chain
3. **End-to-end** - VERIFIED: queries through gateway -> REO node -> `isEligible()` returns true

## Completed

- [x] Created goal documentation ([Goal.md](./Goal.md))
- [x] Surveyed existing local network components (19 services, 3 contract deployment phases)
- [x] Identified `issuance.json` already referenced in `graph-contracts/run.sh` but issuance contracts not yet deployed
- [x] Explored REO contract in `graphprotocol/contracts` post-audit branch
- [x] Explored REO node at `/git/local/eligibility-oracle-node/eligibility-oracle-node`
- [x] Explored deployment package scripts and documentation for local network feasibility
- [x] Identified deployment package gaps and REO node contract signature mismatch
- [x] Created REO node Dockerfile, run.sh, docker-compose override
- [x] Fixed deployment package: added localNetwork support (chain 1337) on post-audit branch
- [x] Added Phase 4 (REO) to `graph-contracts/run.sh` with idempotency, RM integration, ORACLE_ROLE grant
- [x] Fixed REO node ABI mismatch: added `bytes calldata data` param and `uint256` return type
- [x] Updated `CONTRACTS_COMMIT` in `.env` to post-audit branch (`0003fe3a`)
- [x] Fixed address book compatibility: deployment package writes `implementationDeployment` field that indexer-agent rejects; added cleanup step in Phase 4
- [x] Fixed docker-compose override: added `.env` bind mount for REO node container
- [x] End-to-end verified: gateway queries -> Redpanda -> REO node -> on-chain eligibility

## Up Next

- [ ] Clean run test: `docker compose down -v && up` to verify full lifecycle from scratch
- [x] Document testing procedure in `docs/flows/`
- [x] Create automated test script (`scripts/test-reo-eligibility.sh`)

## Gaps To Fix

### ~~1. Deployment package: extend for local network (chain 1337) deployment~~ FIXED

**Branch:** `post-audit` in `graphprotocol/contracts` (commit `bcf73964`)

**What was done:**

- `rocketh/config.ts`: added `graphLocalNetworkChain` (id: 1337) and `localNetwork` environment
- `hardhat.config.ts`: added chain 1337 descriptor and `localNetwork` network config (`http://chain:8545`, test mnemonic)
- `lib/address-book-utils.ts`: added `isLocalNetworkMode()` detection and `addresses-local-network.json` resolution for all three packages (horizon, subgraph-service, issuance)
- `00_sync.ts`: no changes needed - chain 1337 naturally passes the `31337` guard, address book resolution handles the rest
- Docs: added localNetwork to quick reference, local network section in LocalForkTesting.md, fixed broken README link

**Governance handling:** Deploy scripts check if deployer has GOVERNOR_ROLE on-chain. In local network (same account), TXs execute directly inline - no governance batch files needed.

### ~~5. REO node: contract signature mismatch~~ FIXED

**Where:** `/git/local/eligibility-oracle-node/eligibility-oracle-node/crates/eligibility-oracle/src/blockchain.rs`

**What was done:**

- Updated `sol!` macro: `renewIndexerEligibility(address[] calldata indexers, bytes calldata data) external returns (uint256)`
- Added `Bytes` import from `alloy::primitives`
- Updated call site to pass `Bytes::new()` as the `data` parameter
- Verified: `cargo check -p eligibility-oracle` passes clean

### ~~6. Deployment package: `06_integrate.ts` hardcodes `canExecuteDirectly=false`~~ FIXED

**Branch:** `post-audit` in `graphprotocol/contracts` (commit `5e23cde8`)

**What was done:**

- Query `eth_accounts` from the provider to check if the governor key is available
- If governor is in the accounts list (e.g., mnemonic-derived), execute directly with governor as executor
- If not (e.g., Safe multisig in production), generate governance TX file as before
- Removed `requireDeployer` dependency since executor is now the governor

### 7. Indexer-agent: strict address book validation

**Status:** Worked around in local network; upstream fix recommended

The indexer-agent validates address book JSON entries and rejects any with unknown fields. The deployment package (post-audit) now writes `implementationDeployment` and `proxyDeployment` metadata to address books, causing the agent to crash with:

```
Address book entry contains invalid fields: implementationDeployment
```

**Local workaround:** Phase 4 in `graph-contracts/run.sh` strips these fields from `horizon.json` and `subgraph-service.json` after deployment.

**Proper fix:** The indexer-agent should use permissive parsing that extracts known fields and ignores unknown ones. This would prevent breakage as the address book format evolves.

## Notes

### Contract Deployment Approach

Phase 4 in `graph-contracts/run.sh` runs the full REO lifecycle via a single deployment package invocation, plus one cast call for ORACLE_ROLE:

```bash
# Full lifecycle: sync → deploy → configure → transfer → integrate → verify
cd /opt/contracts/packages/deployment
npx hardhat deploy --tags rewards-eligibility --network localNetwork --skip-prompts

# Grant ORACLE_ROLE (not part of standard deployment - local network specific)
cast send ... --private-key="${ACCOUNT1_SECRET}" "${reo_address}" "grantRole(bytes32,address)" "${oracle_role}" "${ACCOUNT0_ADDRESS}"
```

### REO Node Architecture

- Consumes `gateway_queries` topic (already published by gateway in local network)
- Persists aggregated metrics to compacted `indexer_daily_metrics` topic
- Runs in daemon mode (periodic cycles) or single invocation
- Uses Alloy for contract interaction, rdkafka for Redpanda
- Needs `librdkafka` in container (rdkafka crate dependency)

### Local Network Tuning

Default REO node config is for production (28-day windows, 3-hour cycles). For local testing need shorter values - see [Goal.md](./Goal.md#configuration-for-local-network).

### Accounts

- `ACCOUNT0` (0xf39F...) - deployer, ORACLE_ROLE on REO, signing key for REO node
- `ACCOUNT1` (0x7099...) - governor role in contracts, GOVERNOR_ROLE on REO (after configure)
- `RECEIVER` (0xf4EF...) - indexer

### Decisions Made

- Use the deployment package scripts for contract deployment (not local forge/cast workarounds)
- REO node to run in daemon mode with shortened intervals for local testing
- ACCOUNT0 as both NetworkOperator and ORACLE_ROLE holder
- Skip governance transfer step in local network (deployer keeps GOVERNOR_ROLE)

### Prerequisites for Testing

- `CONTRACTS_COMMIT` in `.env` must point to a commit on post-audit that includes localNetwork support
- The post-audit branch must be pushed to GitHub (Docker build clones from there)

---

## Log

### 2026-02-18 - Project started

- Created [Goal.md](./Goal.md) and this status document
- Explored REO contract in `graphprotocol/contracts` post-audit branch: upgradeable proxy pattern, role-based access, time-based eligibility with fail-safe
- Explored REO node: Rust service, Redpanda consumer, batched on-chain submission, no Dockerfile yet
- Identified key integration point: `RewardsManager.setRewardsEligibilityOracle()` connects the two systems
- Local network already has the `gateway_queries` Redpanda topic from gateway service

### 2026-02-18 - Deployment package analysis

- Analysed deployment scripts in `packages/deployment/deploy/rewards/eligibility/`
- Identified 5 gaps blocking local network deployment (see Gaps section above)
- Critical finding: REO node has ABI mismatch with contract (`renewIndexerEligibility` missing `data` param)
- Decision: fix deployment package rather than create local workarounds
- Proceeding with REO node containerisation (independent of contract deployment)

### 2026-02-18 - REO node containerisation

- Created `eligibility-oracle-node/Dockerfile` (multi-stage: rust-builder + wrapper-dev)
- Created `eligibility-oracle-node/run.sh` (generates config.toml, creates Redpanda topic, starts daemon)
- Created `overrides/eligibility-oracle/docker-compose.yaml` (override pattern like indexing-payments)
- Symlinked source from `/git/local/eligibility-oracle-node/eligibility-oracle-node`
- Config uses relaxed local network thresholds: 1-day window, 1 min online day, 60s cycle interval
- Uses `ACCOUNT0_SECRET` as the oracle signing key (needs ORACLE_ROLE granted once contract is deployed)
- Updated overrides/README.md with eligibility oracle section

### 2026-02-18 - Checked post-audit branch

- Switched target from `baseline` to `post-audit` branch (freshly rebased with all changes)
- Confirmed deployment package gap still present on `post-audit`: no chain 1337 / localNetwork support
- Fork-based testing (chain 31337 + FORK_NETWORK) works fine - this is a new capability needed, not a broken feature
- Rephrased gap #1 to clarify the distinction

### 2026-02-18 - Fixed deployment package for local network

- Added localNetwork support to `packages/deployment` on `post-audit` branch (commit `bcf73964`)
- Changes: `rocketh/config.ts` (chain 1337 + environment), `hardhat.config.ts` (chain descriptor + network), `address-book-utils.ts` (`isLocalNetworkMode()` + `addresses-local-network.json` resolution)
- `00_sync.ts` works as-is: chain 1337 bypasses the `31337` guard, address books resolve via updated path functions
- Governance TX handling confirmed: deploy scripts check `hasRole(GOVERNOR_ROLE, deployer)` on-chain, execute directly when true
- Fixed broken README link (`DeploymentDesignPrinciples.md` -> `deploy/ImplementationPrinciples.md`)
- Added localNetwork to DeploymentSetup.md quick reference table
- Added local network section to LocalForkTesting.md

### 2026-02-18 - Phase 4 and REO node ABI fix

- Added Phase 4 (REO) to `graph-contracts/run.sh`:
  - Idempotency check via `issuance.json` + on-chain code check
  - Pre-populates NetworkOperator (ACCOUNT0) in issuance address book
  - Runs `npx hardhat deploy --tags rewards-eligibility-configure --network localNetwork --skip-prompts`
  - Integrates REO with RewardsManager via cast (ACCOUNT1 governor key)
  - Grants ORACLE_ROLE to ACCOUNT0 via cast
- Fixed REO node ABI mismatch in `blockchain.rs`:
  - Updated sol! macro to match contract: `renewIndexerEligibility(address[], bytes) returns (uint256)`
  - Added `Bytes` import, pass `Bytes::new()` at call site
  - Compiles clean: `cargo check -p eligibility-oracle`
- Fixed gap #6: `06_integrate.ts` now checks `eth_accounts` for governor key availability
  - Phase 4 updated to use full `rewards-eligibility` tag (single npx invocation)
  - Only remaining cast call: ORACLE_ROLE grant (local network specific)
- Note: `CONTRACTS_COMMIT` in `.env` needs updating to post-audit (143 commits behind)

### 2026-02-18 - End-to-end integration testing

- Updated `CONTRACTS_COMMIT` in `.env` to `0003fe3a` (post-audit HEAD, already in sync with origin)
- Built all images and started network with REO override
- Phase 4 deployed REO contract at `0x86a2ee8faf9a840f7a2c64ca3d51209f9a02081d`
- RewardsManager integrated, ORACLE_ROLE granted to ACCOUNT0
- **Bug found**: indexer-agent crashes with `Address book entry contains invalid fields: implementationDeployment`
  - Cause: deployment package (post-audit) writes `implementationDeployment` metadata to horizon.json
  - indexer-agent strictly validates address book fields and rejects unknown ones
  - Fix: added `jq walk(... del(.implementationDeployment, .proxyDeployment))` cleanup after Phase 4 in run.sh
  - This is arguably an indexer-agent bug (should ignore unknown fields, not reject them)
- **Bug found**: REO node container missing `.env` bind mount
  - Override only had `./config/local:/opt/config:ro`, not `./.env:/opt/config/.env:ro`
  - Caused `CHAIN_ID: unbound variable` crash
  - Fix: added `.env` bind mount to override's volumes
- After fixes, full flow verified:
  - Sent 10 queries through gateway (subgraph `BFr2mx7...`)
  - REO node consumed 11 messages from `gateway_queries` (10 + 1 from gateway health check)
  - Evaluated: 1 eligible indexer (`0xf4ef...`), days_online=1, good_queries=11
  - Submitted `renewIndexerEligibility` on-chain (tx `0x0f48d617...`)
  - `isEligible(0xf4ef...)` returns `true` on-chain

### 2026-02-18 - Demonstration script and testing documentation

- Created `scripts/test-reo-eligibility.sh`: automated full-cycle test
  - Enables eligibility validation on the REO contract (default is disabled)
  - Seeds `lastOracleUpdateTime` via empty `renewIndexerEligibility([])` to disable fail-safe
  - Verifies indexer is NOT eligible (deny-by-default)
  - Sends queries through gateway, waits for REO node cycle (75s)
  - Verifies indexer IS eligible after REO submission
- Created `docs/flows/EligibilityOracleTesting.md`: step-by-step manual and automated testing guide
  - Includes contract behaviour reference table (three layers: validation toggle, fail-safe, per-indexer)
  - Troubleshooting section for common issues
- Note: previous e2e test did not verify initial ineligibility — only checked `isEligible()` after REO had already submitted. The new script properly demonstrates the full deny→allow transition
