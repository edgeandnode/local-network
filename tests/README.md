# Integration Tests

Automated integration tests for the local network. Each test maps to a specific
operation from the [BaselineTestPlan](../../graphprotocol/contracts/reo-testing/packages/issuance/docs/testing/reo/BaselineTestPlan.md),
[IndexerTestGuide](../../graphprotocol/contracts/reo-testing/packages/issuance/docs/testing/reo/IndexerTestGuide.md),
or [ReoTestPlan](../../graphprotocol/contracts/reo-testing/packages/issuance/docs/testing/reo/ReoTestPlan.md).

## Running

Requires the local network running (`docker compose up -d` from the repo root).

```bash
cd tests
cargo nextest run --no-capture
```

All tests share a single blockchain and run serially (configured in
[.config/nextest.toml](.config/nextest.toml)).

## Test Mapping

### BaselineTestPlan Coverage

| Cycle | Test | Automated Test | File |
|-------|------|---------------|------|
| 1.1 | Indexer stake visible | `indexer_registered` | `network_state.rs` |
| 1.2 | Indexer URL + geoHash | `indexer_registered` | `network_state.rs` |
| 1.3 | Provision exists | `provision_exists` | `network_state.rs` |
| 2.1 | Add stake (Explorer) | `add_stake` | `stake_management.rs` |
| 2.2 | Unstake tokens | `unstake_idle_tokens` | `stake_management.rs` |
| 3.1 | View provision | `provision_exists` | `network_state.rs` |
| 3.2 | Add to provision | `provision_lifecycle` | `provision_management.rs` |
| 3.3 | Thaw from provision | `provision_lifecycle` | `provision_management.rs` |
| 3.4 | Deprovision | `provision_lifecycle` | `provision_management.rs` |
| 4.1 | Active allocations exist | `active_allocations` | `network_state.rs` |
| 4.2 | Create allocation | `close_and_recreate_allocation` | `allocation_lifecycle.rs` |
| 4.3 | Create via actions queue | Indexer CLI workflow | — |
| 4.4 | Create via deployment rules | Indexer CLI workflow | — |
| 4.5 | Reallocate | Indexer CLI workflow | — |
| 5.1 | Gateway query serving | `gateway_serves_queries` + `gateway_query_serving` + `gateway_queries_generate_tap_receipts` | `network_state.rs`, `allocation_lifecycle.rs`, `query_fees.rs` |
| 5.2 | Close allocation + rewards | `close_and_recreate_allocation` + `close_allocation_collects_rewards` | `allocation_lifecycle.rs` |
| 5.3 | TAP escrow state | `tap_escrow_state_observable` (observational only, no assertions) | `query_fees.rs` |
| 5.4 | Close with explicit POI | Indexer CLI workflow | — |
| 6.1 | Indexer health metrics | `indexer_health_metrics` | `network_state.rs` |
| 6.2 | Epoch progression | `epoch_progressing` | `network_state.rs` |
| 6.3 | Log review | Manual | — |
| 7 | End-to-end (close+create) | `close_and_recreate_allocation` | `allocation_lifecycle.rs` |

### IndexerTestGuide (REO) Coverage

| Set | Test | Automated Test | File |
|-----|------|---------------|------|
| Prereqs | REO contract state | `reo_contract_state` | `network_state.rs` |
| 1 | Prepare allocations | Covered by `close_and_recreate_allocation` (setup) | `allocation_lifecycle.rs` |
| 2 | Eligible → close → rewards > 0 | `eligibility_lifecycle` (Set 2) | `eligibility.rs` |
| 3 | Ineligible → close → rewards = 0 | `eligibility_lifecycle` (Set 3) | `eligibility.rs` |
| 4 | Re-renew → close → full rewards | `eligibility_lifecycle` (Set 4) | `eligibility.rs` |
| 5 | Validation disabled | `disable_validation_emergency` | `reo_governance.rs` |

### ReoTestPlan Coverage (Coordinator/Governance)

| Cycle | Test | Automated Test | File |
|-------|------|---------------|------|
| 1.3 | Default parameters | `deployment_parameters` | `reo_governance.rs` |
| 1.4 | RewardsManager → REO | `rewards_manager_integration` | `reo_governance.rs` |
| 1.5 | Contract not paused | `contract_not_paused` | `reo_governance.rs` |
| 2.1 | All eligible (validation off) | Covered by `disable_validation_emergency` | `reo_governance.rs` |
| 2.2 | No renewal history eligible | Covered by `disable_validation_emergency` | `reo_governance.rs` |
| 2.3 | Rewards flow (validation off) | Covered by baseline tests | `allocation_lifecycle.rs` |
| 3.1 | Grant oracle role | Testnet only (account0 has all roles locally) | — |
| 3.2 | Renew single indexer + events | `renew_single_indexer` | `reo_governance.rs` |
| 3.3 | Batch renewal | `batch_renewal` | `reo_governance.rs` |
| 3.4 | Zero address skipped | `zero_address_skipped` | `reo_governance.rs` |
| 3.5 | Unauthorized renewal reverts | `unauthorized_renewal_reverts` | `reo_governance.rs` |
| 4.1+4.2 | Enable validation, eligible stays | `enable_validation_eligible_stays` | `reo_governance.rs` |
| 4.3 | Non-renewed indexer ineligible | Covered by `eligibility_lifecycle` Set 3 | `eligibility.rs` |
| 4.4 | Period expiry | `eligibility_expires_after_period` | `reo_governance.rs` |
| 5.1 | Timeout fail-open | `timeout_failopen` | `reo_governance.rs` |
| 5.2 | Renewal resets timeout | `oracle_renewal_resets_timeout` | `reo_governance.rs` |
| 6.1 | Eligible → rewards | `eligibility_lifecycle` (Set 2) | `eligibility.rs` |
| 6.2 | Ineligible → denied | `eligibility_lifecycle` (Set 3) | `eligibility.rs` |
| 6.3 | Denied rewards → stake unchanged | `eligibility_lifecycle` (Set 3 stake check) | `eligibility.rs` |
| 6.4 | Re-renewal restores rewards | `eligibility_lifecycle` (Set 4) | `eligibility.rs` |
| 6.5 | View functions zero for ineligible | `rewards_view_zero_for_ineligible` | `reo_governance.rs` |
| 6.6 | Optimistic full rewards | `eligibility_lifecycle` (Set 4) | `eligibility.rs` |
| 7.1 | Pause blocks writes | `pause_blocks_writes` | `reo_governance.rs` |
| 7.2 | Disable validation (emergency) | `disable_validation_emergency` | `reo_governance.rs` |
| 7.3 | Access control | `access_control_unauthorized` | `reo_governance.rs` |
| 1.1 | Proxy + implementation | Testnet only | — |
| 1.2 | Role assignments | Testnet only | — |
| 8.1-8.3 | Explorer UI verification | Requires Explorer team | — |

### Additional Coverage (not in test plans)

| Test | What it verifies | File |
|------|-----------------|------|
| `collect_indexing_rewards_increases_stake` | Direct `SubgraphService.collect(IndexingRewards)` contract call | `reward_collection.rs` |

## Test Files

| File | Purpose | Tests |
|------|---------|-------|
| `network_state.rs` | Read-only state observation (Cycles 1, 3.1, 4.1, 6) | 7 |
| `stake_management.rs` | Stake add/remove (Cycle 2) | 2 |
| `provision_management.rs` | Provision add/thaw/deprovision (Cycle 3) | 1 |
| `allocation_lifecycle.rs` | Allocation create/close + gateway queries (Cycles 4-5, 7) | 3 |
| `query_fees.rs` | TAP receipt generation + escrow state (Cycle 5) | 2 |
| `reward_collection.rs` | Direct reward collection contract call | 1 |
| `eligibility.rs` | REO eligibility lifecycle (IndexerTestGuide Sets 2-4, ReoTestPlan 6.1-6.4/6.6) | 1 |
| `reo_governance.rs` | REO governance operations (ReoTestPlan Cycles 1, 3, 4, 5, 6.5, 7) | 15 |
| **Total** | | **32** |

## Library Modules

The test helper library (`src/`) provides typed wrappers that emulate what
production tools do. Each function is documented with the tool/UI operation
it corresponds to.

| Module | Operations | Emulates |
|--------|-----------|----------|
| `graphql.rs` | Subgraph queries, gateway queries | Explorer, `graphql` CLI |
| `management.rs` | `createAllocation`, `closeAllocation`, `getDeployments` | `graph indexer allocations` CLI |
| `staking.rs` | `stake_tokens`, `unstake_tokens`, `provision_add/thaw/deprovision` | Explorer UI, `graph indexer provisions` CLI |
| `cast.rs` | Contract calls (`cast send/call`), REO governance, rewards view, epoch control | Direct contract interaction, `reo:enable/disable/status` Hardhat tasks |
| `polling.rs` | `advance_epochs`, `advance_time`, `mine_blocks` | Chain time manipulation |

## Not Automated (Requires Testnet)

These items cannot be tested on the local network and must be verified on Arbitrum Sepolia:

- **ReoTestPlan 1.1-1.2**: Proxy implementation address and role assignments (deployment-specific)
- **ReoTestPlan 3.1**: Grant oracle role (account0 already has all roles on local network)
- **ReoTestPlan 8.1-8.3**: Explorer UI displays correct rewards/denial state (requires Explorer team)
- **ReoTestPlan Cycle 6 (multi-indexer)**: Multi-indexer reward cycling (requires 3+ indexers)
- **BaselineTestPlan 4.3-4.5**: Actions queue, deployment rules, reallocate (indexer CLI workflows)
- **BaselineTestPlan 5.4**: Close with explicit POI (indexer CLI workflow)
- **BaselineTestPlan 5.3**: TAP escrow state test is observational only (verifies services are reachable but makes no assertions on escrow balances or `queryFeesCollected`)
- **BaselineTestPlan 6.3**: Log review across indexer components
