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