# DIPs Local Testing - Bug Tracker

## BUG-001: dipper migration not embedded in service binary

**Symptom**: `column "num_candidates" of relation "dipper_reg_indexing_requests" does not exist` on any fresh dipper deployment.

**Root cause**: Migration `20260205000000_add_num_candidates_to_indexing_requests.sql` lives in `dipper-pgregistry/migrations/` but `dipper-service` only embeds migrations from `bin/dipper-service/migrations/`. The embedded migrator never sees it.

**Repo**: `dipper`
**Fix**: Delegated DB migrations to sub-crate migrators.
**PR**: https://github.com/edgeandnode/dipper/pull/571 (merged)

## BUG-002: dipper run.sh hardcodes RecurringCollector as zero address

**Symptom**: dipper returns 503 on all admin RPC calls because it can't interact with the RecurringCollector contract.

**Root cause**: `containers/indexing-payments/dipper/run.sh` has `"recurring_collector": "0x0000000000000000000000000000000000000000"` instead of reading the deployed address from the config volume.

**Repo**: `local-network`
**Fix**: Read address from horizon.json via `contract_addr RecurringCollector.address horizon`. Applied in local-network.
**PR**: local-network fix applied, not submitted as standalone PR

## BUG-003: indexer-service run-dips.sh uses stale config field names

**Symptom**: `Ignoring unknown configuration field: dips.?.allowed_payers`, `dips.?.price_per_entity`, `dips.?.price_per_epoch`. Then: `DIPs enabled but no networks in dips.supported_networks. All proposals will be rejected.`

**Root cause**: `containers/indexer/indexer-service/dev/run-dips.sh` uses old config fields (`allowed_payers`, `price_per_entity`, `price_per_epoch`) that no longer exist in the indexer-rs `DipsConfig` struct. The current fields are `supported_networks`, `min_grt_per_30_days`, `min_grt_per_billion_entities_per_30_days`.

**Repo**: `local-network`
**Fix**: Replaced old fields with `supported_networks = ["hardhat"]` and `[dips.min_grt_per_30_days]`. Applied in local-network.
**PR**: local-network fix applied, not submitted as standalone PR

## BUG-004: register_new_indexing_request does not accept num_candidates

**Symptom**: Studio has no way to specify how many indexers should index a given subgraph. The `num_candidates` value is hardcoded to 3 at the database default level.

**Root cause**: The `register_new_indexing_request` JSON-RPC method and EIP-712 message struct only accept `deployment_id` and `chain_id`. There is no parameter to pass `num_candidates` through from the caller.

**Repo**: `dipper`
**Fix**: Add an optional `num_candidates` field to the EIP-712 message struct, the RPC handler, and the CLI `--num-candidates` flag. Default to 3 when not provided.
**PR**: https://github.com/edgeandnode/dipper/pull/572 (merged)

## BUG-005: TAP subgraph pointed at old Escrow contract instead of Horizon PaymentsEscrow

**Symptom**: Gateway returns 402 for all queries. Indexer-service rejects with "No sender found for signer 0x7099...". Dipper crashes on bootstrap meta query.

**Root cause**: `containers/core/subgraph-deploy/run.sh` deployed the TAP subgraph (`semiotic/tap`) pointing at the old TAP Escrow from `tap-contracts.json`. The `tap-escrow-manager` correctly authorizes signers on the Horizon PaymentsEscrow from `horizon.json`. The subgraph never indexes the Horizon authorization events, so the indexer-service sees no authorized signers.

**Repo**: `local-network`
**Fix**: Changed `contract_addr Escrow tap-contracts` to `contract_addr PaymentsEscrow.address horizon` in subgraph-deploy/run.sh. Applied in local-network.
**PR**: local-network fix applied, not submitted as standalone PR

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
**Fix**: Added idempotent `RewardsManager.setSubgraphService()` call in `containers/core/graph-contracts/run.sh`. Applied in local-network.
**PR**: local-network fix applied, not submitted as standalone PR

## BUG-009: IISA API does not reload scores after cronjob updates them

**Symptom**: IISA selection endpoint returns stale data (e.g. 1 indexer when 10 exist). The cronjob correctly computes and writes updated scores to the shared volume, but the API serves its startup cache indefinitely. This caused dipper to only select 1 of 10 available indexers for a DIPs agreement.

**Root cause**: The IISA HTTP API (`iisa` service) loads scores into an in-memory DataFrame at startup and never reloads them. The `POST /refresh` endpoint exists but nothing calls it. The cronjob writes to `/app/scores/indexer_scores.json` on a shared volume, but the API reads from memory, not disk, on each request.

**Repo**: `subgraph-dips-indexer-selection`
**Fix**: Two-layer approach: (1) The cronjob calls `POST /refresh` on the IISA API after writing scores. (2) The API runs a background task that checks the scores file mtime every `IISA_SCORES_RELOAD_INTERVAL` seconds (default 120) and reloads when it changes.
**PR**: https://github.com/edgeandnode/subgraph-dips-indexer-selection/pull/75 (merged)

## BUG-010: Dipper topology excludes indexers without allocations

**Symptom**: Dipper logs `"IISA selected indexer not found in network topology, skipping"` for every idle indexer. IISA selects 3 candidates from 10, all 10 pass the price filter, but dipper skips all 3 because they have no active allocations.

**Root cause**: Dipper's network topology is built exclusively from subgraph allocation data (`indexerAllocations`). An indexer only enters the topology map when it appears in allocation data. Idle indexers (registered with stake, URL, and operators but no allocations) are invisible. This is a chicken-and-egg problem: DIPs is supposed to create allocations, but dipper can't propose to indexers without existing allocations.

**Repo**: `dipper`
**Fix**: Extended the `indexer_operators` fetcher to also return the URL field, and changed its `Extend<Snapshot>` impl to create indexer entries (`.or_insert_with()`) instead of only modifying existing ones (`.and_modify()`). Now all registered indexers with a valid URL appear in the topology regardless of allocation status.
**PR**: https://github.com/edgeandnode/dipper/pull/581 (merged)

## BUG-011: Extra indexers rejected with SIGNER_NOT_AUTHORISED due to missing escrow accounts

**Symptom**: After fixing BUG-010, dipper sends proposals to idle indexers but all are rejected with `SIGNER_NOT_AUTHORISED`.

**Root cause**: The indexer-service's DIPs signer validator reuses the TAP `EscrowSignerValidator`, which queries the network subgraph for `paymentsEscrowAccounts` filtered by receiver (indexer address). The `tap-escrow-manager` only deposits GRT into PaymentsEscrow for the primary indexer. Extra indexers have no escrow accounts, so the query returns empty and all signers are rejected -- even though the signer authorization (on GraphTallyCollector) exists at the payer level.

**Repo**: `local-network`
**Fix**: Added escrow deposits (GRT approve + `PaymentsEscrow.deposit(collector, receiver, amount)`) for each extra indexer in the `start-indexing-extra` init container generated by `scripts/gen-extra-indexers.py`. In production, the `IndexingAgreementManager` contract (on the `mde/dips-ignition-deployment` branch) handles this automatically when `offerAgreement()` is called. Applied in local-network.
**PR**: local-network fix applied, not submitted as standalone PR

**Update (2026-04-13)**: This bug is effectively dead code after the DIPs migration to offer-based RCA authorization. Indexer-service no longer looks up signer authorization via escrow accounts; it queries the indexing-payments-subgraph for on-chain RCA offers instead. The escrow-deposit step for extra indexers stays in place because TAP still needs it for query-fee collection, but DIPs no longer cares about the escrow signer set. The `SIGNER_NOT_AUTHORISED` gRPC RejectReason now maps internally to `OfferNotFound` / `OfferMismatch` errors.

## BUG-012: Dipper chain_listener disabled — agreements expire despite on-chain acceptance

**Symptom**: Dipper marks agreements as Expired even though indexer-agents accepted them on-chain and created allocations. This causes dipper to repeatedly create new agreements for the same indexing request (over-allocation). For example, a request for 3 indexers ends up with 7+ allocations across multiple reassessment cycles.

**Root cause**: Dipper's `chain_listener` service monitors a subgraph for `IndexingAgreementAccepted` and `IndexingAgreementCanceled` events to transition agreement status from Created to AcceptedOnChain. The chain_listener config is `None` in the local-network run.sh because no such subgraph existed. Without it, agreements stay in Created status until the expiration service marks them Expired (deadline_seconds = 300), regardless of what happened on-chain.

**Repo**: `dipper` (config), `graphprotocol/indexing-payments-subgraph` (data source), `local-network`
**Fix**: Created `graphprotocol/indexing-payments-subgraph` which indexes all IndexingAgreement events from the SubgraphService contract. The subgraph auto-deploys in local-network when DIPs contracts are present. Dipper's `chain_listener` section configured in `containers/indexing-payments/dipper/run.sh`. Dipper configmap example updated upstream.
**PR**: subgraph repo merged. Dipper configmap PR #585 (merged). Local-network run.sh updated.

## BUG-013: RCA metadata version field causes on-chain acceptance to revert

**Symptom**: Every DIPs on-chain acceptance reverts with `IndexingAgreementDecoderInvalidData("decodeRCAMetadata", data)`. The indexer-agent picks up the accepted proposal, attempts `SubgraphService.acceptIndexingAgreement()`, and the contract can't decode the metadata bytes.

**Root cause**: Dipper was encoding `version: 1` in the RCA metadata, but the Solidity enum `IndexingAgreementVersion.V1` has value `0`. The contract decoded version `1` as an unknown variant and reverted. The initial investigation (PR #582) incorrectly attributed this to an `abi_encode` vs `abi_encode_params` mismatch — that PR was closed after testing showed the encoding format was not the issue.

**Repo**: `dipper`
**Fix**: Use `version: 0` for `IndexingAgreementVersion.V1` in the RCA metadata.
**PR**: https://github.com/edgeandnode/dipper/pull/583 (merged)

## BUG-014: Indexer-agent pauses indexing-payments subgraph due to startup race condition

**Symptom**: Dipper's chain_listener reports "Subgraph appears stalled" and never sees on-chain `IndexingAgreementAccepted` events. Agreements that were accepted on-chain by indexer-agents expire in dipper's DB (status 5 = Expired) after `deadline_seconds` (300s). Dipper then reassesses and creates duplicate agreements, leading to over-allocation.

**Root cause**: The indexer-agent's `run-dips.sh` checks once at startup for the indexing-payments subgraph deployment and sets `INDEXER_AGENT_OFFCHAIN_SUBGRAPHS` if found. On a fresh deploy, the agent starts before `subgraph-deploy` finishes deploying the indexing-payments subgraph (they run in parallel with no compose dependency). The single-shot check finds nothing (`INDEXING_PAYMENTS_DEPLOYMENT=`), the env var is never set, and the agent's `reconcileDeployments` subsequently pauses the subgraph because it has no allocation and no offchain rule.

**Repo**: `local-network`
**Fix**: Changed the single check to a wait loop (up to 3 minutes, 5s intervals) that polls for the indexing-payments subgraph before giving up. Applied in `containers/indexer/indexer-agent/dev/run-dips.sh`.
**PR**: local-network fix applied, not submitted as standalone PR

## BUG-015: @graphprotocol/interfaces NPM package stale vs audit-branch contract

**Symptom**: `acceptIndexingAgreement` multicall from indexer-agent reverts on-chain with `FailedCall()` (selector `0xd6bda275`). The agent encodes the call using its installed ABI (`@graphprotocol/interfaces@0.7.0-dips.0`), which declares `acceptIndexingAgreement(address, SignedRCA)` — a two-argument function where the RCA is a 10-field struct. The audit-branch contract has been updated to `acceptIndexingAgreement(address, RCA, bytes)` — three arguments, with the RCA now containing an additional `uint16 conditions` field at position 9 (eleven fields total). The selector the agent sends (`0x0b4baec7`) no longer exists on the deployed contract, so the multicall's `Address.functionDelegateCall` fails with no return data and OpenZeppelin wraps it as `FailedCall()`.

**Root cause**: The audit-branch changes to `IRecurringCollector.RecurringCollectionAgreement` (adding `conditions`) and `ISubgraphService.acceptIndexingAgreement` (splitting the packed `SignedRCA` arg into separate `RCA` and `signature` args) exist on the `mb9/dips-local-testing-fixes` branch of the contracts repo but were never released to NPM. The last published `@graphprotocol/interfaces` version carrying any DIPs changes is the pre-release `0.7.0-dips.0`, cut before these audit-branch updates. Toolshed transitively depends on interfaces via `workspace:^`, so the indexer-agent (which pulls toolshed + interfaces from NPM) ends up with the pre-audit struct shape and function signature.

**Workarounds applied for local-network testing**:

1. `packages/toolshed/src/core/recurring-collector.ts` — committed on `mb9/dips-local-testing-fixes` to add `uint16 conditions` to the RCA decoder tuple so the indexer-agent can decode proposals persisted by indexer-service. This change is permanent, not a hack.
2. `packages/indexer-common/src/indexing-fees/dips.ts` — committed on `fix/getrewards-subgraph-service` to unpack `proposal.signedRca` into separate `rca` and `signature` arguments at both `acceptIndexingAgreement` call sites. This change is permanent, not a hack.
3. Local-only override of `indexer/node_modules/@graphprotocol/toolshed/dist/core/recurring-collector.{js,d.ts}` — copied the rebuilt toolshed output so the container's running code picks up the eleven-field decoder before the NPM package is republished. Ephemeral; wiped by `yarn install`.
4. Local-only override of `indexer/node_modules/@graphprotocol/interfaces/dist/types/**/*.d.ts` — patched the compiled type declarations so TypeScript accepts the three-argument call shape. Ephemeral; wiped by `yarn install`.

**Repo**: `graphprotocol/contracts` (packages `interfaces` and `toolshed`) and `graphprotocol/indexer` (transitive consumer)

**Fix (not yet done)**: Publish new NPM versions of `@graphprotocol/interfaces` and `@graphprotocol/toolshed` from a commit containing the audit-branch struct and function signature changes. Bump the indexer's resolved versions (either by pinning or by running `yarn install` once the versions are live on NPM). At that point, overrides 3 and 4 above can be removed and the indexer-agent's `dips.ts` will type-check and run correctly against stock NPM packages with no further changes. The contracts repo's `pnpm build` currently fails at the interfaces package with "missing module" errors for several TypeChain-generated files; that build failure needs to be resolved before a clean release can be cut.

**PR**: not submitted; blocked on build fix and publish coordination.

## BUG-016: Indexer-agent DIPs accept/rule race — accepting indexers never sync the deployment

**Symptom**: When dipper selects multiple indexers for a DIPs agreement, only some of them end up syncing the accepted deployment. On local-network, a 3-indexer agreement produced 1/3 syncing (agent 2 synced, agents 4 and 5 did not). The failing agents create the on-chain allocation successfully, but their graph-nodes never deploy the subgraph because no `dips`-basis indexing rule is ever persisted. The agent's reconciliation loop then repeatedly tries to unallocate the just-created DIPs allocation with `reason: "group:none"`, which fails with `IE067`.

**Root cause**: Two independent loops in `packages/indexer-common/src/indexing-fees/dips.ts` both key off the `pending_rca_proposals` table:

- **Accept loop** (`startProposalAcceptanceLoop`, every 5s, `DIPS_ACCEPTANCE_INTERVAL`) calls `processProposal` which sends `acceptIndexingAgreement`, waits for the receipt, then calls `consumer.markAccepted` to remove the row from pending.
- **Reconcile loop** (`ensureAgreementRules` via the agent's main tick, every 15s) iterates pending proposals inside `ensureAgreementRulesFromRca` and upserts a `dips` indexing rule for each.

The rule-creation loop requires the proposal to still be pending when the tick fires. Whichever loop "wins" the race to touch the proposal row determines whether the rule gets created. On hardhat, receipt processing takes 4-8 seconds, so rule-creation ticks occasionally catch proposals still pending (agent 2 was lucky). On Arbitrum (block time ~0.25s, receipt confirmation ~1-2s), the accept loop will consistently finish well before the next 15s rule-creation tick, so the rule would practically never be created and DIPs acceptance would silently no-op for every indexer.

The existing `ensureAgreementRulesFromLegacy` path does not help: it iterates `IndexingAgreement`, a local table populated only by the deprecated off-chain voucher system that the RCA flow does not write to. Once `pendingRcaConsumer` is configured (DIPs enabled), `ensureAgreementRules` (dips.ts:146-159) exclusively takes the RCA branch.

**Repo**: `graphprotocol/indexer`
**Fix**: Create the `dips` indexing rule inside `processProposal` before `executeTransaction(acceptIndexingAgreement)` is called. The proposal object already carries everything the rule needs (`subgraphDeploymentId`, `minSecondsPerCollection`, `maxSecondsPerCollection`, derived allocation amount), so this is a local DB upsert with no extra subgraph queries. `ensureAgreementRulesFromRca` stays in place as a defense-in-depth no-op once the rule exists. The existing rejection-cleanup path at `dips.ts:790-807` already removes the rule if the proposal is subsequently rejected, so dangling rules are handled.

Scoped to `fix/getrewards-subgraph-service` (PR #1178). The 5s `startProposalAcceptanceLoop` was introduced by commit `ad6035a5` on that branch — the commit message explicitly calls out the decoupling from the 120s reconciliation loop. Every branch below #1178 (main-dips, #1181, #1185, #1190) runs `acceptPendingProposals` from the main reconciliation tick alongside `ensureAgreementRules`, so accept and rule creation happen on the same cycle and the race cannot occur there. The fix lands as a follow-up commit on #1178, which means no rebase of Maikol's stack is required.

**PR**: fix committed to PR #1178 as `5ebed20d`; a standalone fix PR (#1199) was opened and then closed after the tracing was corrected.