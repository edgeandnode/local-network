# Rewards Eligibility Oracle - Status

> Last updated: 2026-02-18

## Current Phase: Implementation (REO node containerisation)

### Summary

Adding the REO to the local network. Two workstreams:

1. **Contract deployment** - BLOCKED: deployment package needs local network support (see gaps below)
2. **REO node containerisation** - IN PROGRESS: Dockerfile, config, docker-compose

## Completed

- [x] Created goal documentation ([Goal.md](./Goal.md))
- [x] Surveyed existing local network components (19 services, 3 contract deployment phases)
- [x] Identified `issuance.json` already referenced in `graph-contracts/run.sh` but issuance contracts not yet deployed
- [x] Explored REO contract in `graphprotocol/contracts` baseline branch
- [x] Explored REO node at `/git/local/eligibility-oracle-node/eligibility-oracle-node`
- [x] Explored deployment package scripts and documentation for local network feasibility
- [x] Identified deployment package gaps and REO node contract signature mismatch

## In Progress

- [x] Create Dockerfile for REO node
- [x] Create `run.sh` with config generation and local network tuning
- [x] Add docker-compose override service

## Up Next

- [ ] Fix contract signature mismatch in REO node (see gap #5)
- [ ] Fix deployment package gaps (see below) to enable local network deployment
- [ ] Add REO contract deployment phase to `graph-contracts/run.sh`
- [ ] Create compacted `indexer_daily_metrics` Redpanda topic
- [ ] Test end-to-end: queries -> Redpanda -> REO node -> on-chain eligibility
- [ ] Document testing procedure in `flows/`

## Gaps To Fix

### 1. Deployment package: no local network (chain 1337) support

**Where:** `packages/deployment/hardhat.config.ts` and `packages/deployment/rocketh/config.ts`

The deployment package only supports chain IDs 31337 (hardhat/localhost), 421614 (Arbitrum Sepolia), 42161 (Arbitrum One). The local network uses chain ID 1337.

**Fix:** Add chain 1337 as a supported environment (or allow the existing localNetwork config from the subgraph-service package pattern).

### 2. Deployment package: sync step blocks pure local network

**Where:** `packages/deployment/deploy/common/00_sync.ts` (lines 48-58)

The sync step throws an error if running on localhost (chain 31337) without `FORK_NETWORK` set. For a pure local network this needs to be different - the contracts are deployed locally but the sync step doesn't know about them.

**Fix:** Allow the sync step to work against local networks by reading addresses from mounted files or an alternative address book source. The local network already has all prerequisite contracts (Controller, L2GraphToken, RewardsManager) deployed in Phase 1 - their addresses are in `config/local/horizon.json`.

### 3. Deployment package: no address book entries for chain 1337

**Where:** `packages/horizon/addresses.json`, `packages/issuance/addresses.json`

Address books only contain entries for production/testnet chains. For local network deployment, the address books need to be populated with the locally-deployed contract addresses.

**Fix:** Either support runtime address book population from external sources, or add a "localNetwork" entry mechanism.

### 4. Deployment docs: no local network deployment guidance

**Where:** `packages/deployment/docs/deploy/RewardsEligibilityOracleDeployment.md`, `packages/deployment/docs/LocalForkTesting.md`

Docs only cover fork-based testing and production deployment. No guidance for pure local network deployment.

**Fix:** Add local network deployment documentation once the support is implemented.

### 5. REO node: contract signature mismatch

**Where:** `/git/local/eligibility-oracle-node/eligibility-oracle-node/crates/eligibility-oracle/src/blockchain.rs` (line 16)

The node defines:

```solidity
function renewIndexerEligibility(address[] memory _indexers) external;
```

But the contract has:

```solidity
function renewIndexerEligibility(address[] calldata indexers, bytes calldata data) external;
```

The node is missing the `bytes calldata data` parameter. This will cause ABI encoding mismatch - the transaction will revert or be incorrectly encoded at runtime.

**Fix:** Update the sol! macro in the node to include the `data` parameter and pass empty bytes (`Bytes::new()`) when calling.

## Notes

### Contract Deployment Approach

The deployment package (`packages/deployment`) should handle all REO deployment and RM integration. The scripts use rocketh/hardhat-deploy v2 with a tag-based system. For local network, the intended flow would be:

```bash
# Inside graph-contracts container, after Phase 1 completes:
cd /opt/contracts/packages/deployment
npx hardhat deploy --tags rewards-eligibility --network localNetwork
```

This requires the gaps above to be fixed first. The deployment scripts handle:

- Proxy + implementation deployment (`01_deploy.ts`)
- Parameter configuration (`04_configure.ts`)
- Role assignment and governance transfer (`05_transfer_governance.ts`)
- RewardsManager integration (`06_integrate.ts`)

### REO Node Architecture

- Consumes `gateway_queries` topic (already published by gateway in local network)
- Persists aggregated metrics to compacted `indexer_daily_metrics` topic
- Runs in daemon mode (periodic cycles) or single invocation
- Uses Alloy for contract interaction, rdkafka for Redpanda
- Needs `librdkafka` in container (rdkafka crate dependency)

### Local Network Tuning

Default REO node config is for production (28-day windows, 3-hour cycles). For local testing need shorter values - see [Goal.md](./Goal.md#configuration-for-local-network).

### Accounts

Need to decide which Hardhat account gets ORACLE_ROLE. Current accounts:

- `ACCOUNT0` (0xf39F...) - deployer, used for most contract interactions
- `ACCOUNT1` (0x7099...) - governor role in contracts
- `RECEIVER` (0xf4EF...) - indexer
- Could use `ACCOUNT0` or a dedicated account for the oracle

### Decisions Made

- Use the deployment package scripts for contract deployment (not local forge/cast workarounds)
- REO node to run in daemon mode with shortened intervals for local testing

### Blockers

- Contract deployment blocked on deployment package gaps (#1-#4)
- REO node integration blocked on contract signature mismatch (#5) for on-chain submission

---

## Log

### 2026-02-18 - Project started

- Created [Goal.md](./Goal.md) and this status document
- Explored REO contract in `graphprotocol/contracts` baseline branch: upgradeable proxy pattern, role-based access, time-based eligibility with fail-safe
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
