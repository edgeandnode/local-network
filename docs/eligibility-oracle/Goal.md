# Rewards Eligibility Oracle - Goal

## Objective

Add the Rewards Eligibility Oracle (REO) to the local network so that indexer reward eligibility can be tested end-to-end. This involves two pieces:

1. **REO contract** - Deploy and configure the `RewardsEligibilityOracle` contract, integrate it with the `RewardsManager`
2. **REO node** - Containerise and run the eligibility-oracle-node service that consumes gateway query data from Redpanda and submits eligible indexers on-chain

## Background

The REO determines which **indexers** are eligible for rewards based on their query-serving performance. This is not the Subgraph Availability Oracle (SAO) and has nothing to do with subgraph denial.

### How It Works

1. The **gateway** publishes query attempt data to the `gateway_queries` Redpanda topic (already exists in local network)
2. The **REO node** consumes these events, aggregates per-indexer metrics over a rolling window (28 days default), and evaluates eligibility based on:
   - Minimum online days (default: 5)
   - Minimum subgraphs served (default: 1)
   - Maximum latency (default: 5000ms)
   - Maximum blocks behind (default: 50000)
3. Eligible indexers are submitted on-chain via `renewIndexerEligibility()` on the REO contract
4. The **RewardsManager** checks `rewardsEligibilityOracle.isEligible(indexer)` when distributing rewards

### REO Contract Design

- **Deny by default**: indexers are not eligible until an authorized oracle calls `renewIndexerEligibility()`
- **Time-based**: eligibility expires after `eligibilityPeriod` (default: 14 days) and must be renewed
- **Fail-safe**: if oracles stop updating for `oracleUpdateTimeout` (default: 7 days), all indexers become eligible
- **Global toggle**: `eligibilityValidationEnabled` can disable all eligibility checks (default: disabled)
- **Role-based access**: GOVERNOR, OPERATOR, ORACLE, PAUSE roles

## What Success Looks Like

1. **REO contract deployed** as part of `graph-contracts` setup, integrated with `RewardsManager` via `setRewardsEligibilityOracle()`
2. **REO node running** in docker-compose, consuming from local Redpanda `gateway_queries` topic
3. **Indexer marked eligible** after serving queries through the gateway
4. **Rewards gated by eligibility** - can verify via `isEligible()` contract calls and reward distribution behaviour

## Components

### Existing (already in local network)

- **graph-contracts** - Deploys Horizon protocol contracts including `RewardsManager`; `issuance.json` already referenced but issuance package not yet deployed
- **gateway** - Publishes query data to `gateway_queries` Redpanda topic
- **redpanda** - Kafka-compatible message broker, already running
- **graph-node** - Indexes subgraphs, serves queries
- **indexer-agent / indexer-service** - Indexer infrastructure

### To Be Added

- **REO contract deployment** - Add Phase 4 to `graph-contracts/run.sh` using issuance package deployment scripts from `packages/deployment/deploy/rewards/eligibility/`
- **REO node containerisation** - Create Dockerfile for the Rust service at `/git/local/eligibility-oracle-node/eligibility-oracle-node`
- **REO node docker-compose service** - Config, Redpanda connection, chain RPC, contract address, signing key
- **Redpanda topic setup** - Create compacted `indexer_daily_metrics` topic for REO node state persistence

## Source Repositories

| Component                         | Location                                                               | Branch     |
| --------------------------------- | ---------------------------------------------------------------------- | ---------- |
| REO contract + deployment scripts | `/git/graphprotocol/contracts`                                         | `post-audit` |
| REO contract source               | `packages/issuance/contracts/eligibility/RewardsEligibilityOracle.sol` |            |
| REO deployment scripts            | `packages/deployment/deploy/rewards/eligibility/`                      |            |
| REO node (Rust service)           | `/git/local/eligibility-oracle-node/eligibility-oracle-node`           |            |

## Implementation Tasks

### 1. Contract Deployment & Integration

- Update `CONTRACTS_COMMIT` in `.env` to point to `post-audit` branch
- Add local network (chain 1337) support to `packages/deployment` (see [Status.md](./Status.md#gaps-to-fix))
- Add REO contract deployment as a new phase in `graph-contracts/run.sh`
- Configure roles: grant ORACLE_ROLE to the REO node's signing key
- Integrate with RewardsManager: call `setRewardsEligibilityOracle(reoAddress)`
- Write deployed address to `issuance.json`

### 2. REO Node Containerisation

- Create Dockerfile for the Rust workspace at `/git/local/eligibility-oracle-node/eligibility-oracle-node`
- Create `config.toml` template with local network values:
  - `kafka.bootstrap_servers` = `redpanda:9092`
  - `kafka.input_topic` = `gateway_queries`
  - `blockchain.rpc_urls` = `["http://chain:8545"]`
  - `blockchain.contract_address` = from `issuance.json`
  - `blockchain.chain_id` = `1337`
  - `blockchain.private_key` = signing key with ORACLE_ROLE
- Add to docker-compose (likely as an override like indexing-payments)

### 3. Redpanda Topic Setup

- Create compacted `indexer_daily_metrics` topic for REO node persistence
- May need a setup script or init container

### 4. Testing & Validation

- Send queries through the gateway to generate `gateway_queries` events
- Verify REO node processes events and submits eligibility on-chain
- Check `isEligible(indexerAddress)` returns true
- Verify reward distribution honours eligibility

## Configuration for Local Network

For local testing, sensible overrides to the REO node defaults:

- Shorter `analysis_period_days` (e.g., 1 day instead of 28)
- Lower `min_online_days` (e.g., 1 instead of 5)
- Shorter `scheduling.interval_secs` (e.g., 60 instead of 10800)
- Shorter `staleness_threshold_hours` (e.g., 1 instead of 20)
- Consider starting with `eligibilityValidationEnabled = false` on the contract and enabling once the node is running

## Related Documentation

- [Local Network README](../../README.md)
- [REO Contract Spec](file:///git/graphprotocol/contracts/post-audit/packages/issuance/contracts/eligibility/RewardsEligibilityOracle.md)
- [REO Deployment Guide](file:///git/graphprotocol/contracts/post-audit/packages/deployment/docs/deploy/RewardsEligibilityOracleDeployment.md)
