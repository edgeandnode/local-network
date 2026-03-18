# DIPs Local Testing - Bug Tracker

## BUG-001: dipper migration not embedded in service binary

**Symptom**: `column "num_candidates" of relation "dipper_reg_indexing_requests" does not exist` on any fresh dipper deployment.

**Root cause**: Migration `20260205000000_add_num_candidates_to_indexing_requests.sql` lives in `dipper-pgregistry/migrations/` but `dipper-service` only embeds migrations from `bin/dipper-service/migrations/`. The embedded migrator never sees it.

**Repo**: `dipper`
**Fix**: Either move the migration into `bin/dipper-service/migrations/` or change the embedded migrator to include `dipper-pgregistry/migrations/`.
**PR**: fixed locally on `fix/delegate-migrations-to-subcrates` branch

## BUG-002: dipper run.sh hardcodes RecurringCollector as zero address

**Symptom**: dipper returns 503 on all admin RPC calls because it can't interact with the RecurringCollector contract.

**Root cause**: `containers/indexing-payments/dipper/run.sh` has `"recurring_collector": "0x0000000000000000000000000000000000000000"` instead of reading the deployed address from the config volume.

**Repo**: `local-network`
**Fix**: Read address from horizon.json via `contract_addr RecurringCollector.address horizon`. Already applied locally.
**PR**: not submitted

## BUG-003: indexer-service run-dips.sh uses stale config field names

**Symptom**: `Ignoring unknown configuration field: dips.?.allowed_payers`, `dips.?.price_per_entity`, `dips.?.price_per_epoch`. Then: `DIPs enabled but no networks in dips.supported_networks. All proposals will be rejected.`

**Root cause**: `containers/indexer/indexer-service/dev/run-dips.sh` uses old config fields (`allowed_payers`, `price_per_entity`, `price_per_epoch`) that no longer exist in the indexer-rs `DipsConfig` struct. The current fields are `supported_networks`, `min_grt_per_30_days`, `min_grt_per_billion_entities_per_30_days`.

**Repo**: `local-network`
**Fix**: Replace old fields with `supported_networks = ["hardhat"]` and `[dips.min_grt_per_30_days]`. Already applied locally.
**PR**: not submitted

## BUG-004: register_new_indexing_request does not accept num_candidates

**Symptom**: Studio has no way to specify how many indexers should index a given subgraph. The `num_candidates` value is hardcoded to 3 at the database default level.

**Root cause**: The `register_new_indexing_request` JSON-RPC method and EIP-712 message struct only accept `deployment_id` and `chain_id`. There is no parameter to pass `num_candidates` through from the caller.

**Repo**: `dipper`
**Fix**: Add an optional `num_candidates` field to the EIP-712 message struct, the RPC handler, and the CLI `--num-candidates` flag. Default to 3 when not provided.
**PR**: https://github.com/edgeandnode/dipper/pull/572

## BUG-005: TAP subgraph pointed at old Escrow contract instead of Horizon PaymentsEscrow

**Symptom**: Gateway returns 402 for all queries. Indexer-service rejects with "No sender found for signer 0x7099...". Dipper crashes on bootstrap meta query.

**Root cause**: `containers/core/subgraph-deploy/run.sh` deployed the TAP subgraph (`semiotic/tap`) pointing at the old TAP Escrow from `tap-contracts.json`. The `tap-escrow-manager` correctly authorizes signers on the Horizon PaymentsEscrow from `horizon.json`. The subgraph never indexes the Horizon authorization events, so the indexer-service sees no authorized signers.

**Repo**: `local-network`
**Fix**: Changed `contract_addr Escrow tap-contracts` to `contract_addr PaymentsEscrow.address horizon` in subgraph-deploy/run.sh. Applied locally.
**PR**: not submitted

## BUG-006: RecurringCollector address missing from horizon.json on fresh deploy

**Symptom**: Dipper restart loop with `"1337".RecurringCollector.address not found in /opt/config/horizon.json`.

**Root cause**: The `saveToAddressBook` function in contracts toolshed (`packages/toolshed/src/deployments/horizon/contracts.ts`) has a `GraphHorizonContractNameList` whitelist. `RecurringCollector` was deployed on-chain by Ignition but silently dropped from the address book because it wasn't in the whitelist. The fix exists on the `mde/dips-ignition-deployment` branch.

**Repo**: `contracts`
**Fix**: Cherry-picked commits `3998337a` (adds RecurringCollector ignition module) and `15380514` (adds to whitelist) onto `escrow-management`. Also requires `pnpm build:self` in `packages/toolshed` to compile the TS change to JS.
**PR**: exists on `mde/dips-ignition-deployment` branch (not yet merged to `escrow-management`)

## BUG-007: HorizonStaking Ignition module missing dependency on GraphPeripheryModule

**Symptom**: `graph-contracts` fails with `GraphDirectoryInvalidZeroAddress("GraphToken")` during contract deployment. Nondeterministic -- may work on some branches and fail on others.

**Root cause**: `packages/horizon/ignition/modules/core/HorizonStaking.ts` deploys HorizonStaking without an `after` dependency on `GraphPeripheryModule`. The HorizonStaking constructor extends `GraphDirectory`, which queries the Controller for GraphToken, EpochManager, RewardsManager, etc. These are registered in the Controller by `GraphPeripheryModule`. Without the explicit dependency, Ignition may schedule HorizonStaking before the periphery registrations, causing the constructor to read `address(0)` and revert. Every other core module (GraphPayments, PaymentsEscrow, GraphTallyCollector, RecurringCollector) has `{ after: [GraphPeripheryModule, HorizonProxiesModule] }` but HorizonStaking was missing it.

**Repo**: `contracts`
**Fix**: Add `{ after: [GraphPeripheryModule, HorizonProxiesModule] }` to the `deployImplementation` call in `HorizonStaking.ts`. Applied locally on `indexing-payments-management-audit`.
**PR**: not submitted

## BUG-008: SubgraphService not registered as rewards issuer in RewardsManager

**Symptom**: indexer-agent fails all allocation operations (reallocate, new allocations for DIPs) with `execution reverted: "Not a rewards issuer"`. The agent enters a perpetual retry loop, blocking both protocol subgraph reallocations and DIPs agreement acceptance.

**Root cause**: The `AllocationManager.stakeUsageSummary()` calls `RewardsManager.getRewards(SubgraphService, allocationId)` before executing allocation transactions. The RewardsManager checks whether the caller (SubgraphService at `0x09635F...`) is a registered rewards issuer. On a fresh local-network deploy, SubgraphService is never whitelisted in the RewardsManager, so all `getRewards` calls revert.

**Repo**: `local-network` (deploy scripts)
**Fix**: The deploy scripts need to call `RewardsManager.setRewardsIssuer(SubgraphService, true)` after contract deployment. Needs investigation into which deploy script should handle this and what the RewardsManager ABI looks like.
**PR**: not submitted

## BUG-009: IISA API does not reload scores after cronjob updates them

**Symptom**: IISA selection endpoint returns stale data (e.g. 1 indexer when 10 exist). The cronjob correctly computes and writes updated scores to the shared volume, but the API serves its startup cache indefinitely. This caused dipper to only select 1 of 10 available indexers for a DIPs agreement.

**Root cause**: The IISA HTTP API (`iisa` service) loads scores into an in-memory DataFrame at startup and never reloads them. The `POST /refresh` endpoint exists but nothing calls it. The cronjob writes to `/app/scores/indexer_scores.json` on a shared volume, but the API reads from memory, not disk, on each request.

**Repo**: `subgraph-dips-indexer-selection`
**Fix**: Two-layer approach applied locally: (1) The cronjob now calls `POST /refresh` on the IISA API after writing scores (`IISA_API_URL` env var, warns at startup if unset). (2) The API now runs a background task that checks the scores file mtime every `IISA_SCORES_RELOAD_INTERVAL` seconds (default 120) and reloads when it changes. The cronjob provides immediate freshness; the periodic reload is a fallback if the refresh call fails.
**PR**: https://github.com/edgeandnode/subgraph-dips-indexer-selection/pull/75

## BUG-010: Dipper topology excludes indexers without allocations

**Symptom**: Dipper logs `"IISA selected indexer not found in network topology, skipping"` for every idle indexer. IISA selects 3 candidates from 10, all 10 pass the price filter, but dipper skips all 3 because they have no active allocations.

**Root cause**: Dipper's network topology is built exclusively from subgraph allocation data (`indexerAllocations`). An indexer only enters the topology map when it appears in allocation data. Idle indexers (registered with stake, URL, and operators but no allocations) are invisible. This is a chicken-and-egg problem: DIPs is supposed to create allocations, but dipper can't propose to indexers without existing allocations.

**Repo**: `dipper`
**Fix**: Extended the `indexer_operators` fetcher to also return the URL field, and changed its `Extend<Snapshot>` impl to create indexer entries (`.or_insert_with()`) instead of only modifying existing ones (`.and_modify()`). Now all registered indexers with a valid URL appear in the topology regardless of allocation status.
**PR**: not submitted

## BUG-011: Extra indexers rejected with SIGNER_NOT_AUTHORISED due to missing escrow accounts

**Symptom**: After fixing BUG-010, dipper sends proposals to idle indexers but all are rejected with `SIGNER_NOT_AUTHORISED`.

**Root cause**: The indexer-service's DIPs signer validator reuses the TAP `EscrowSignerValidator`, which queries the network subgraph for `paymentsEscrowAccounts` filtered by receiver (indexer address). The `tap-escrow-manager` only deposits GRT into PaymentsEscrow for the primary indexer. Extra indexers have no escrow accounts, so the query returns empty and all signers are rejected -- even though the signer authorization (on GraphTallyCollector) exists at the payer level.

**Repo**: `local-network`
**Fix**: Added escrow deposits (GRT approve + `PaymentsEscrow.deposit(collector, receiver, amount)`) for each extra indexer in the `start-indexing-extra` init container generated by `scripts/gen-extra-indexers.py`. In production, the `IndexingAgreementManager` contract (on the `mde/dips-ignition-deployment` branch) handles this automatically when `offerAgreement()` is called.
**PR**: not submitted

## BUG-012: Dipper chain_listener disabled — agreements expire despite on-chain acceptance

**Symptom**: Dipper marks agreements as Expired even though indexer-agents accepted them on-chain and created allocations. This causes dipper to repeatedly create new agreements for the same indexing request (over-allocation). For example, a request for 3 indexers ends up with 7+ allocations across multiple reassessment cycles.

**Root cause**: Dipper's `chain_listener` service monitors a subgraph for `IndexingAgreementAccepted` and `IndexingAgreementCanceled` events to transition agreement status from Created to AcceptedOnChain. The chain_listener config is `None` in the local-network run.sh because no such subgraph existed. Without it, agreements stay in Created status until the expiration service marks them Expired (deadline_seconds = 300), regardless of what happened on-chain.

**Repo**: `dipper` (config), `graphprotocol/indexing-payments-subgraph` (data source)
**Fix**: Created `graphprotocol/indexing-payments-subgraph` which indexes all IndexingAgreement events from the SubgraphService contract. The subgraph auto-deploys in local-network when DIPs contracts are present. Remaining work: configure dipper's `chain_listener` section in `containers/indexing-payments/dipper/run.sh` to point at this subgraph.
**PR**: subgraph repo created and merged (graphprotocol/indexing-payments-subgraph). Dipper config not yet updated.

## BUG-013: RCA metadata ABI encoding mismatch causes on-chain acceptance to revert

**Symptom**: Every DIPs on-chain acceptance reverts with `IndexingAgreementDecoderInvalidData("decodeRCAMetadata", data)`. The indexer-agent picks up the accepted proposal, attempts `SubgraphService.acceptIndexingAgreement()`, and the contract can't decode the metadata bytes.

**Root cause**: Alloy's `SolValue::abi_encode()` on a struct with dynamic fields (`bytes`) wraps the encoding with a 32-byte outer tuple offset (`0x20` prefix, 224 bytes total). Solidity's `abi.encode()` for the same struct does not include this prefix (192 bytes). The SubgraphService contract calls `abi.decode(rca.metadata, (AcceptIndexingAgreementMetadata))` which expects Solidity's format. The extra `0x20` prefix causes the decoder to misalign and revert.

**Repo**: `dipper`
**Fix**: Switch from `.abi_encode()` to `.abi_encode_params()` in `into_sol_rca()` (`bin/dipper-service/src/indexer_rpc_client.rs`). The `_params` variant produces the inner encoding without the outer offset, matching Solidity's format.
**PR**: https://github.com/edgeandnode/dipper/pull/582