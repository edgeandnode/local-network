# Rewards Eligibility Oracle - Status

> Last updated: 2026-02-18

## Current Phase: Research & Planning

### Summary

Adding the REO to the local network. Two workstreams: (1) deploy the REO contract and integrate with RewardsManager, (2) containerise and run the REO node that consumes from Redpanda.

## Completed

- [x] Created goal documentation ([Goal.md](./Goal.md))
- [x] Surveyed existing local network components (19 services, 3 contract deployment phases)
- [x] Identified `issuance.json` already referenced in `graph-contracts/run.sh` but issuance contracts not yet deployed
- [x] Explored REO contract in `graphprotocol/contracts` baseline branch
  - Contract: `packages/issuance/contracts/eligibility/RewardsEligibilityOracle.sol`
  - Deployment scripts: `packages/deployment/deploy/rewards/eligibility/` (6 steps)
  - Interfaces: `IRewardsEligibility`, `IRewardsEligibilityAdministration`, `IRewardsEligibilityReporting`, `IRewardsEligibilityStatus`
  - RM integration: `RewardsManager.setRewardsEligibilityOracle()` with ERC165 validation
- [x] Explored REO node at `/git/local/eligibility-oracle-node/eligibility-oracle-node`
  - Rust service, consumes `gateway_queries` from Redpanda
  - Evaluates indexer eligibility over rolling window
  - Submits via `renewIndexerEligibility()` batched calls
  - No Dockerfile yet - needs containerisation
  - TOML config: kafka, eligibility thresholds, blockchain, scheduling

## In Progress

- [ ] Determine how to deploy REO contract in local network (Hardhat deployment scripts vs forge)
- [ ] Determine which account/key gets ORACLE_ROLE for the REO node

## Up Next

- [ ] Update `CONTRACTS_COMMIT` or add baseline branch support for issuance package
- [ ] Add REO contract deployment phase to `graph-contracts/run.sh`
- [ ] Grant ORACLE_ROLE and integrate with RewardsManager
- [ ] Create Dockerfile for REO node
- [ ] Create `config.toml` with local network values
- [ ] Add docker-compose service (override or main)
- [ ] Create compacted `indexer_daily_metrics` Redpanda topic
- [ ] Test end-to-end: queries -> Redpanda -> REO node -> on-chain eligibility
- [ ] Document testing procedure in `flows/`

## Notes

### Contract Deployment

The existing `graph-contracts/run.sh` deploys in 3 phases (Horizon, TAP, DataEdge). The REO deployment needs a Phase 4 using the issuance package. The deployment scripts in `packages/deployment/deploy/rewards/eligibility/` use Hardhat tasks (`deploy:protocol` pattern). Key steps:

1. Deploy proxy + implementation (`01_deploy.ts`)
2. Configure parameters (`04_configure.ts`)
3. Transfer governance (`05_transfer_governance.ts`)
4. Integrate with RM (`06_integrate.ts`)

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

_None yet._

### Blockers

_None identified._

---

## Log

### 2026-02-18 - Project started

- Created [Goal.md](./Goal.md) and this status document
- Explored REO contract in `graphprotocol/contracts` baseline branch: upgradeable proxy pattern, role-based access, time-based eligibility with fail-safe
- Explored REO node: Rust service, Redpanda consumer, batched on-chain submission, no Dockerfile yet
- Identified key integration point: `RewardsManager.setRewardsEligibilityOracle()` connects the two systems
- Local network already has the `gateway_queries` Redpanda topic from gateway service
