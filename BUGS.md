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

**Symptom (two distinct manifestations)**:

- *Without override #5 (most common)*: every `acceptIndexingAgreement` call from the agent throws `UNSUPPORTED_OPERATION` / `shortMessage: "no matching fragment"` from ethers before any tx is sent. The agent's `handleAcceptError` classifies this as transient and retries every 5s for the full 300s RCA deadline. Every agreement expires (status 5 in dipper). After two reassessment rounds, dipper's 30-day decline-lookback effectively blocklists every `(indexer, deployment)` pair, and subsequent registrations log `No candidates selected to fulfill the indexing request`.
- *With override #5 but with override #3/#4 stale (rarer)*: the call reaches the chain and reverts on-chain with `FailedCall()` (selector `0xd6bda275`). The agent encodes the call using a stale 2-arg `acceptIndexingAgreement(address, SignedRCA)` selector (`0x0b4baec7`) that no longer exists on the deployed contract; the multicall's `Address.functionDelegateCall` fails with no return data and OpenZeppelin wraps it as `FailedCall()`.

In both cases the underlying mismatch is the same: the audit-branch contract has `acceptIndexingAgreement(address, RCA, bytes)` (3 args, with the RCA containing an additional `uint16 conditions` field at position 9 — eleven fields total), and the indexer's installed ABI/types still describe the pre-audit 2-arg packed-`SignedRCA` form.

**Root cause**: The audit-branch changes to `IRecurringCollector.RecurringCollectionAgreement` (adding `conditions`) and `ISubgraphService.acceptIndexingAgreement` (splitting the packed `SignedRCA` arg into separate `RCA` and `signature` args) exist on the `mb9/dips-local-testing-fixes` branch of the contracts repo but were never released to NPM. The last published `@graphprotocol/interfaces` version carrying any DIPs changes is the pre-release `0.7.0-dips.0`, cut before these audit-branch updates. Toolshed transitively depends on interfaces via `workspace:^`, so the indexer-agent (which pulls toolshed + interfaces from NPM) ends up with the pre-audit struct shape and function signature.

**Workarounds applied for local-network testing**:

1. `packages/toolshed/src/core/recurring-collector.ts` — committed on `mb9/dips-local-testing-fixes` to add `uint16 conditions` to the RCA decoder tuple so the indexer-agent can decode proposals persisted by indexer-service. This change is permanent, not a hack.
2. `packages/indexer-common/src/indexing-fees/dips.ts` — committed on `fix/getrewards-subgraph-service` to unpack `proposal.signedRca` into separate `rca` and `signature` arguments at both `acceptIndexingAgreement` call sites. This change is permanent, not a hack.
3. Local-only override of `indexer/node_modules/@graphprotocol/toolshed/dist/core/recurring-collector.{js,d.ts}` — copied the rebuilt toolshed output so the container's running code picks up the eleven-field decoder before the NPM package is republished. Ephemeral; wiped by `yarn install`.
4. Local-only override of `indexer/node_modules/@graphprotocol/interfaces/dist/types/contracts/**/*.d.ts` (specifically `subgraph-service/ISubgraphService.d.ts`, `toolshed/ISubgraphServiceToolshed.d.ts`, `horizon/IRecurringCollector.d.ts`, `issuance/allocate/IIndexingAgreementManager.d.ts`) — patched the compiled type declarations so the agent's `lerna prepare` step (which runs strict `tsc`) accepts the three-argument call shape and the `conditions` field. Without this, `lerna prepare` exits 1 and the agent container exits before reaching `tsx`. Ephemeral; wiped by `yarn install`.
5. Local-only override of `indexer/node_modules/@graphprotocol/interfaces/dist/types/factories/contracts/**/*__factory.js` (specifically `subgraph-service/ISubgraphService__factory.js` and `toolshed/ISubgraphServiceToolshed__factory.js`). **This is the runtime ABI source.** `getInterface(name)` in `@graphprotocol/interfaces/dist/src/index.js` calls `factory.createInterface()` from these files; the resulting ethers Interface is what the agent uses to encode every `acceptIndexingAgreement` call. Without this override, every accept attempt throws `UNSUPPORTED_OPERATION: no matching fragment` and the 300s RCA deadline expires before any agreement lands. Override #4 alone is not sufficient — `.d.ts` files are compile-time only and do not affect ethers' runtime fragment resolution. Ephemeral; wiped by `yarn install`. Source: copy from `contracts/packages/interfaces/dist/types/factories/contracts/**/*__factory.js` after a clean `pnpm build` in `packages/interfaces`.

**Repo**: `graphprotocol/contracts` (packages `interfaces` and `toolshed`) and `graphprotocol/indexer` (transitive consumer)

**Fix (not yet done)**: Publish new NPM versions of `@graphprotocol/interfaces` and `@graphprotocol/toolshed` from a commit containing the audit-branch struct and function signature changes. Bump the indexer's resolved versions (either by pinning or by running `yarn install` once the versions are live on NPM). At that point, overrides 3, 4, and 5 above can be removed and the indexer-agent's `dips.ts` will type-check and run correctly against stock NPM packages with no further changes.

**On the contracts-repo build (corrected diagnosis)**: An earlier note in this entry claimed the contracts repo's `pnpm build` fails at the interfaces package with "missing module" errors. That was a misdiagnosis — incremental rebuilds were inheriting stale TypeChain output (`types/**/index.ts` files referencing files that no longer exist) and the `is_newer` mtime cache in `packages/interfaces/scripts/build.sh` was letting the inconsistency survive. A clean build (`pnpm clean && pnpm build` in `packages/interfaces`) on `mb9/dips-local-testing-fixes` produces a correct dist with the eleven-field RCA struct and the three-argument `acceptIndexingAgreement` baked in. The build pipeline is therefore not a blocker; cutting a release is purely an NPM publish step gated on security approval.

**Operating note**: Overrides 3 (toolshed `cp`), 4 (interfaces `.d.ts`), and 5 (interfaces `__factory.js`) need to be reapplied any time something bumps `yarn.lock` mtime above `node_modules/.yarn-install-stamp` (a `git pull`, branch switch, or manual `yarn install`). The agent's `run-dips.sh` skips the install when the stamp is newer, so overrides survive a vanilla container restart but not a yarn-lock change. After applying overrides, restart all indexer-agent containers — ethers caches the contract interface at process start; running agents will not pick up new factory ABIs without a restart.

**Secondary issue (worth a small follow-up PR)**: The agent's `dips.ts:handleAcceptError` classifies ethers `UNSUPPORTED_OPERATION` errors as transient and keeps retrying for the full 300s RCA deadline. When the underlying cause is an ABI-fragment mismatch (override 5 missing or stale), the call is deterministically broken — retrying buys nothing and burns the deadline. With 50 concurrent requests this also amplifies into dipper's 30-day decline-lookback table, blocklisting every `(indexer, deployment)` pair and producing the secondary `No candidates selected to fulfill the indexing request` failure mode. A clearer classification — treat `UNSUPPORTED_OPERATION` with `operation: "fragment"` as non-recoverable, mark rejected immediately with the parsed reason — would surface this class of failure in seconds rather than 5 minutes and would prevent the cascade through reassessment into the decline table.

**PR**: not submitted; blocked on publish approval only.

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

**PR**: fix committed to PR #1178 as `f36225a0` (after rebasing the branch onto current `feat/dips-on-chain-cancel` to drop 20 stale commits); a standalone fix PR (#1199) was opened and then closed after the tracing was corrected.

## BUG-017: DIPs end-to-end pipeline can't fit a 50-request burst inside the 300s RCA deadline

**Symptom**: Under load (50 indexing requests registered in a single burst against 6 indexers, num_candidates=3), 50 of the 150 resulting agreements expire (status 5) at the 300s mark. Successful accepts in the same burst show p99 create→accept of 4:57 and a max of 5:02 — already inches from the 300s wall. Dipper reassessment then creates 50 fresh agreements which accept successfully against the now-mostly-empty pipeline.

**Measured numbers (50-request burst on 6 indexers, 50 distinct deployments)**:

```
ACCEPTED agreements (150)             min 0:07  p50 3:30  p90 4:32  p99 4:57  max 5:02
EXPIRED  agreements (50)              ~5:06–5:16 lifetime; 40/50 had offer_tx submitted
```

The 5-minute ceiling on the successful path is what should jump out — the deadline isn't 5 minutes of slack with average behaviour, it's already the operating point.

**Root cause (three pressure points stacking)**:

1. **Dipper offer submission is single-wallet sequential.** Every `offer()` is a separate tx through one signer's nonce queue. 50 deployments × 3 candidates = 150 offers serialised through one mempool slot.
2. **Indexer-agent's `processProposal` is serial within an agent's accept loop.** `startProposalAcceptanceLoop` ticks every 5s and processes the queue one proposal at a time. With ~25 proposals per agent at 50-request scale, the queue can't drain inside 5 minutes.
3. **`graphNode.ensure` runs inside `processProposal`.** First-deploy-of-subgraph latency stacks per-agreement. Could be hoisted to run once per deployment instead of per agreement (or run earlier, e.g. when the rule is created in `ensureDipsRuleForProposal`).

Any one of these would tighten the budget; all three together break it at this scale.

**Repo**: `dipper` (offer submission), `graphprotocol/indexer` (indexer-agent accept loop and graphNode.ensure placement), `local-network` (deadline_seconds config).

**Operational mitigation applied (2026-04-29)**: Bumped `deadline_seconds` from 300 to 600 in `local-network/containers/indexing-payments/dipper/run.sh`. Doubles the available budget without touching any of the underlying serialisation. The 50-request stress test should now have meaningful headroom; in production a longer deadline is also safer than 300s under realistic load.

**Real fixes (not yet done)**: Address the three pressure points. Order from least to most invasive:

1. Move `graphNode.ensure` out of `processProposal` and into rule creation (`ensureDipsRuleForProposal`) so the cold-deploy cost happens once per deployment, not once per agreement.
2. Allow the agent's accept loop to process proposals in parallel (bounded concurrency, e.g. up to N in flight). The `acceptIndexingAgreement` call itself is independent per-proposal.
3. Batch dipper's `offer()` submissions via multicall, or accept that single-wallet nonce ordering is fundamentally serial and provision multiple signer wallets.

**PR**: not submitted; recorded for follow-up.

## BUG-018: 76 active on-chain allocations have no backing IndexingAgreement entity

**Symptom (observed 2026-04-29 after the 50-request stress test in BUG-017)**:

```
on-chain (graph-network subgraph)              226 active allocations
indexing-payments subgraph                     150 IndexingAgreement entities (all Accepted)
dipper DB                                      150 ACCEPTED + 50 EXPIRED
```

76 on-chain allocations exist with no matching IndexingAgreement entity in the indexing-payments subgraph. Cross-referenced against dipper, the (indexer, deployment) pairs of these stranded allocations all have a status-5 EXPIRED record in dipper's DB. Dipper paid exactly once per (indexer, deployment) pair (zero duplicate ACCEPTED agreements), so dipper isn't double-paying — but indexers are doing indexing work that won't be paid for. With 18 of those pairs holding 2 active allocations each, the same indexer is sometimes carrying both a paid allocation and a stranded one for the same deployment.

**Root cause**: The indexer-agent's reconciliation loop trusts that any active `dips`-basis indexing rule it carries should be satisfied by an active allocation. When something kills the originally-paired agreement (dipper expires it, dipper rejects it, the agent itself gets restarted and loses the in-flight context), the rule survives. Reconciliation then keeps the deployment allocated either by leaving the existing on-chain allocation alone or by creating a fresh one via `startService` — without an agreement backing it. The agent never queries indexing-payments-subgraph to verify "this allocation has a paying agreement"; it trusts dipper's earlier signal and never re-checks.

The architectural gap: the agent treats dipper's promises as durable invariants, but dipper can change its mind (reassessment, expiration, rejection) and the agent has no way to learn about that change after the initial accept.

**Repo**: `graphprotocol/indexer`

**Fix (proposed, not yet implemented)**: Add a periodic sweep on the indexer-agent that reconciles each `dips`-basis allocation against the indexing-payments-subgraph. Design points settled with Samuel:

- *Oracle*: indexing-payments-subgraph. Single batched query `indexingAgreements(where: { indexer: SELF })`, diff the returned set against the agent's active dips allocations.
- *Staleness guard*: read the chain timestamp from the subgraph response (`_meta.block.timestamp`). If the response's chain time is recent (e.g. within a small bound of wall-clock), trust the result. If the timestamp is days/months/years old, treat the subgraph as unreliable and skip the sweep this tick.
- *Action on miss*: disable the `dips` indexing rule, then let normal agent reconciliation close the allocation through its existing path. Don't close allocations directly from the sweep — that bypasses too much accounting.
- *What counts as a miss*: no IndexingAgreement entity for the (agreementId / indexer / deployment) tuple, or entity exists but state is not Accepted. Brief windows where chain_listener / subgraph hasn't caught up to a just-accepted allocation are filtered by the staleness guard.

This makes the agent self-protective: regardless of dipper's behaviour, the agent only keeps `dips`-basis allocations alive while the indexing-payments subgraph confirms there's a paying agreement for them. Defends against dipper bugs marking accepted agreements expired, dipper restarts losing in-flight state, stale rules surviving DB resets, and the kind of reassessment-induced orphan we're seeing here.

**PR**: not submitted; design agreed, implementation deferred.

## BUG-019: gateway drops studio-published DIPs deployment — deploy script uploads a JSON manifest the network subgraph's YAML-only parser can't read (network=null)

**Symptom**: Gateway returns `subgraph not found: QmUvDoZbS7HJhqb4WzT51LkMDS4bSXWn7C3GfExE1vAjC1` for the studio-published subgraph that has an Accepted DIPs agreement, even though the deployment is synced + healthy on graph-node and has an active on-chain allocation (`0x6178bb67...`). Querying it through the gateway (`/api/deployments/id/Qm...`) or by subgraph id fails. Gateway logs show `subgraph=4MH9Uz1z... err=manifest missing network` during pre-processing, and `subgraphs=3 deployments=2 indexings=2` — only 2 of the 3 published deployments are usable.

**Root cause** (verified): The deployment's IPFS manifest is serialized as **JSON**, while `graph deploy` (and every real deployment) uploads **YAML**. `local-network/scripts/deploy-studio-test-subgraphs.py:make_ipfs_manifest()` builds the IPFS manifest with `json.dumps(...)`, so QmUvDoZbS7's manifest on IPFS is `{"specVersion":"0.0.4", ... "network":"hardhat", ... "startBlock":1}`. graph-node accepts JSON manifests fine (YAML is a JSON superset), so it indexes the deployment correctly. But the graph-network subgraph's manifest handler `handleSubgraphDeploymentManifest` (`src/mappings/ipfs.ts`) does **naive YAML string-splitting**, not real parsing: network via `manifest.split('network: ', 2)`, schema via `split('schema:\n')`, startBlock by counting `source:` vs `startBlock: ` tokens. A JSON manifest contains none of those YAML tokens (`"network": "hardhat"` has a quote+colon, not `network: `), so the splits return length 1, leaving `network = null` and `startBlock = 0`. The gateway's `network::pre_processing` then hard-drops any deployment whose `manifest.network` is null (`err=manifest missing network`), so the deployment is never added to the routable set. The two working deployments (block-oracle DataEdge `QmPJaxGgG3...`, network subgraph) were deployed with YAML manifests by standard tooling, so their `network` parses to `"hardhat"`.

**Verified**:
- `ipfs cat QmUvDoZbS7...` → starts with `{"specVersion": "0.0.4", ...}` — **JSON**, with `"network": "hardhat"`, `"startBlock": 1`.
- `ipfs cat QmPJaxGgG3...` (working) → starts with `dataSources:\n  - kind: ethereum` — **YAML**.
- graph-network `subgraphDeploymentManifests`: QmUvDoZbS7 `{network:null, startBlock:"0"}`; QmPJaxGgG3 + QmU9fn4xn2 `{network:"hardhat", startBlock:"1"}`.
- graph-network-subgraph `src/mappings/ipfs.ts` `handleSubgraphDeploymentManifest` parses via `manifest.split('network: ', 2)` etc. (YAML-only string-split, confirmed against `master`).
- `deploy-studio-test-subgraphs.py:make_ipfs_manifest()` returns `json.dumps({...})` (line ~167) — the JSON source.
- gateway logs: `pre_processing subgraph=4MH9Uz1z... err=manifest missing network` → `subgraphs=3 deployments=2 indexings=2`; direct gateway query → `{"errors":[{"message":"subgraph not found: QmUvDoZbS7..."}]}`.
- graph-node `indexingStatuses`: QmUvDoZbS7 synced, healthy, latestBlock 57362.
- graph-network `allocations`: active allocation `0x6178bb67...` by indexer `0xf4ef6650...` for QmUvDoZbS7 — so the **only** gateway blocker is `network=null`.

**Impact on Studio DIPs UI testing**: The Playground "send queries to gateway" feature and the Endpoints "gateway query url" feature are wired correctly (has-accepted-agreement returns true; the studio-ui gateway proxy enforces origin + session and forwards to the gateway with the API key injected). But a live gateway query for the published subgraph returns the gateway's `subgraph not found` because of this manifest gap — so the end-to-end "real data through the gateway" hop can't be demonstrated until the deployment is routable.

**Repo**: `local-network` owns the root-cause fix. `graph-network-subgraph` owns an optional secondary hardening.

**Fix (canonical, no hack)** — `local-network`: change `make_ipfs_manifest()` in `scripts/deploy-studio-test-subgraphs.py` to emit **YAML** (matching what `graph deploy` uploads and what `make_manifest()` already emits for the build step), instead of `json.dumps`. This makes studio-seeded deployments structurally identical to real ones, so the network subgraph parses `network: hardhat` and the gateway routes them. Because the manifest bytes change, the deployment **CID changes** — the existing QmUvDoZbS7 (immutable JSON) stays unservable; a re-deploy under the fixed script yields a new, routable hash that must be (re)published + (re)allocated.

**Fix (optional hardening)** — `graph-network-subgraph`: make `handleSubgraphDeploymentManifest` parse the manifest robustly (detect a leading `{` and read `network`/`startBlock` via `json.fromBytes`, or use a real YAML parse) instead of string-splitting on YAML-only tokens. graph-node accepts JSON manifests, so the network subgraph should too. Not required for testnet (real manifests are YAML) but prevents the same silent `network=null` drop for any JSON-or-oddly-formatted manifest. Submit upstream PR.

**PR**: not submitted. Root cause verified and located. Canonical fix is the one-function YAML change in local-network.

## BUG-020: indexer rejects all paid queries to an Active allocation whose RAV was already redeemed on-chain ("Allocation already redeemed")

**Classification**: testing-infra / environment corruption from a local-chain reorg. **Not a product bug**, independent of and predating the BUG-019 manifest fix. Logged because it silently blocks gateway→indexer queries and any component that pays the indexer (dipper bootstrap, iisa), and the failure mode is non-obvious.

**Symptom**: Gateway queries to the network subgraph deployment `QmU9fn4xn2WZ2xTBwUswyqxQqt7DmbLTQhm5dQ5sMfXxur` fail with `bad indexers: {0xf4ef6650...: BadResponse(400)}`. indexer-service rejects every TAP receipt for allocation `0x9aA76d737249D307D4e1Ffd35531695e52334B46` with `Receipt error: Issue encountered while performing check: Allocation already redeemed (v2): 0x9aA76d73...`. Because the network subgraph is the deployment dipper/iisa poll through the gateway (client `0x70997970...`), their bootstrap stays stuck and dipper reports `unhealthy`.

**Root cause** (verified): The allocation `0x9aa76d73...` has an **on-chain-redeemed RAV while the allocation is still Active** (in Horizon V2, redeeming a RAV collects query fees and is independent of closing the allocation). indexer-service's V2 receipt check rejects new receipts for a collection whose RAV is already redeemed, so every paid query to that allocation 400s. The redeemed-while-active state is the anomaly; the most plausible origin is the chain reorg this run (head rolled back 57362→57307, recovered by mining forward) reverting an allocation-close after its RAV had been redeemed, leaving the on-chain collector with a redeem for an allocation that is once again Active.

**The check source is ON-CHAIN, not the local DB** (empirically proven, correcting an earlier wrong theory): setting `tap_horizon_ravs.redeemed_at = NULL` for the collection **and** restarting `indexer-service` did **not** clear the rejection — the "already redeemed" verdict is re-derived from on-chain collector/escrow state (or equivalent persistent source), not from `redeemed_at` and not from `tap_horizon_denylist` (which is empty and sender-keyed). The DB edit was reverted.

**Verified**:
- Nulling `tap_horizon_ravs.redeemed_at` for `collection_id = 0000…0000_9aa76d73…52334b46` then restarting indexer-service → query still `BadResponse(400)`, same `Allocation already redeemed (v2)` log ⇒ source is not that column.
- `tap_horizon_denylist` is empty (0 rows) and keyed by `sender_address`, not allocation ⇒ not the denylist.
- graph-network `allocations`: `0x9aa76d73...` is `status: Active`, `createdAtBlockNumber: 124`, `closedAtBlockNumber: null` — Active, never closed; yet its RAV is redeemed ⇒ redeemed-while-active.
- indexer-service logs: repeated `Allocation already redeemed (v2): 0x9aA76d73...` survive an indexer-service restart.
- gateway logs: only candidate for `QmU9fn4xn2W...` is allocation `0x9aa76d73...`; `indexer_request ... result=Err(BadResponse("400"))`. dipper bootstrap loops on `GET /api/deployments/id/QmU9fn4xn2W...` → `failed to fetch subgraphs info` (attempt 230+).

**Does NOT block the Studio DIPs gateway-query fix**: a query to any *other* allocation carries a different `collection_id` the collector has no redeem for, so it passes. The re-deployed `QmeHi72t...` got a **fresh** allocation `0x9337feff...` and a paid gateway query returned real data (`block.number 57391`) — proving the BUG-019 fix end-to-end. This bug only blocks paths pinned to the one redeemed allocation (the network subgraph), i.e. dipper/iisa bootstrap and therefore minting a *new* DIPs agreement.

**Repo**: none owns a product fix — this is environment state from a reorg, not code. On-chain "already redeemed" semantics are correct.

**Recovery (environment only — normal indexer ops, no DB editing)**: rotate the allocation. Toggle the indexer-agent rule for `QmU9fn4xn2W...` to `decisionBasis: never` so the agent closes `0x9aa76d73...`, then back to `always` so it opens a **fresh** allocation with a new `collection_id` the collector has never recorded a redeem for — paid queries then pass and dipper bootstraps. (Editing `redeemed_at` was tried and does **not** work — the state is on-chain.) A full `down -v` + re-seed also clears it but destroys all existing publishes/agreements. **Hardening idea (optional, upstream `indexer-rs`)**: when an allocation is observed Active on-chain, don't treat a prior reverted redeem as terminal for that collection; not required for testnet where deep reorgs don't occur.

**PR**: not submitted — environment corruption, no product code owner. Hardening idea noted for `indexer-rs` if reorg resilience is desired.

## BUG-021: studio-ui Playground gateway proxy can't reach the gateway and sends an empty API key — local-network never exports GATEWAY_API_KEY and points the proxy at a host-only URL

**Symptom**: With an Accepted DIPs agreement, the Playground (Feature 2) is supposed to send queries through the server-side proxy `packages/ui/src/pages/api/gateway/query/[deploymentId].ts`, which forwards to the gateway with the studio API key in the auth header so the key is never exposed to the browser. On local-network the proxy fails two ways: (1) it authenticates with an **empty** Bearer token (`auth error: invalid authorization header` from the gateway), and (2) even with a key it targets `http://localhost:7700/api`, which from inside the `studio-ui` container resolves to the container itself, not the gateway — the fetch returns connection-refused (`000`).

**Root cause** (verified): The proxy and the Endpoints display both call the single `getGatewayBase()` in `packages/ui/src/utils/gateway/base.ts`, which returned `process.env.LOCAL_GATEWAY_QUERY_URL || 'http://localhost:7700/api'`. That one URL has to serve two contexts at once and can't: the **client** Endpoints display needs the host-mapped `localhost:7700` (the user copies it and queries from the host), while the **server** Playground proxy runs inside the container and needs the in-network `gateway:7700`. Separately, `local-network/containers/ui/studio/ui.sh` sourced `GATEWAY_API_KEY` from `.env` but only exported it under the inlined alias `STUDIO_CLIENT_SIDE_GATEWAY_API_KEY`; the bare `GATEWAY_API_KEY` the proxy reads (`process.env.GATEWAY_API_KEY`) was never exported, so it was empty in the next-server process → empty Bearer.

**Verified**:
- In-container `curl http://localhost:7700/...` → `000` (connection refused); `curl http://gateway:7700/api/deployments/id/QmeHi72tDgrZ2XWoVBdKxVEPfzPipNSiHU6Rp5aLskH1Fc` with `Bearer deadbeef…` (len 32) → `{"data":{"_meta":{"block":{"number":57458}}}}` — the in-network host + real key is the working hop.
- Before the fix, the next-server (`/proc/<pid>/environ`) had no `GATEWAY_API_KEY` and `LOCAL_GATEWAY_QUERY_URL=http://localhost:7700/api` only.
- `getGatewayBase()` is shared by `SubgraphEndpoints/utils.ts:mapTheGraphNetworkToGateway` (Feature 1, called from the **client** hook `useUrlBuilder`) and `pages/api/gateway/query/[deploymentId].ts:64` (Feature 2, **server**). `LOCAL_GATEWAY_PROXY_URL` is deliberately not in `inlinedEnv.mjs`, so it is `undefined` in the browser and defined only server-side.

**Repo**: `local-network` owns the container-wiring fix; `subgraph-studio` owns the `getGatewayBase()` split (server-only proxy URL).

**Fix (canonical, no hack)**:
- `local-network/containers/ui/studio/ui.sh`: add `export GATEWAY_API_KEY="${GATEWAY_API_KEY}"` (server-only, not inlined → never shipped to the browser) and add `export LOCAL_GATEWAY_PROXY_URL="http://gateway:7700/api"` alongside the existing host-facing `LOCAL_GATEWAY_QUERY_URL="http://localhost:${GATEWAY_PORT}/api"` (keep both).
- `subgraph-studio` `packages/ui/src/utils/gateway/base.ts`: **split into two accessors** rather than one shared function. `getGatewayDisplayBase()` (Endpoints display, called from the client hook `useUrlBuilder`) reads only the host-facing `LOCAL_GATEWAY_QUERY_URL` → always `localhost:7700`, identical on SSR and client. `getGatewayBase()` (server proxy only) prefers `LOCAL_GATEWAY_PROXY_URL` → `gateway:7700`. `SubgraphEndpoints/utils.ts:mapTheGraphNetworkToGateway` now calls `getGatewayDisplayBase()`; `pages/api/gateway/query/[deploymentId].ts` keeps `getGatewayBase()`.
- **Why split, not one shared function:** the app is the Next.js pages router. `pages/subgraph/[name]/[[...tab]].tsx:getServerSideProps` feeds `subgraph.publishedSubgraphs`, which `SubgraphDetails.context.tsx` seeds into the xstate context **synchronously**, so at SSR `publishedNetworks.length > 0` is true and `getGatewayBase()` runs **server-side** where `LOCAL_GATEWAY_PROXY_URL` is defined — a single shared function would bake `gateway:7700` into the Endpoints display HTML (then flip to `localhost` on hydration: mismatch + transient wrong copyable URL). The display accessor never reading the proxy var removes that leak structurally, independent of env-inlining timing.

**Verified after fix**: next-server env now has `GATEWAY_API_KEY` (len 32), `LOCAL_GATEWAY_PROXY_URL=http://gateway:7700/api`, and `LOCAL_GATEWAY_QUERY_URL=http://localhost:7700/api`; in-container gateway query returns block 57458; `base.test.ts` 8/8 pass — `getGatewayBase` prefers the proxy URL, `getGatewayDisplayBase` ignores it so the display can never emit `gateway:7700`.

**PR**: not submitted. local-network change committed to this repo; subgraph-studio `base.ts` + test change needs a PR to that repo (branch `daniel/playground-gateway-query`).

## BUG-022: both DIPs Studio features stay dark on local-network — the indexing-payments subgraph query is disabled because `INDEXING_PAYMENTS_SUBGRAPH_ENABLED` is never exported to next-server

**Symptom**: Even with the gateway wiring fixed (BUG-021) and an Accepted agreement present in the indexing-payments subgraph, neither DIPs feature lights up in the Studio UI: the Endpoints tab keeps showing the dev query URL (Feature 1) and the Playground keeps sending to the dev/upgrade-indexer URL (Feature 2). Both features gate on `hasAcceptedAgreement`, which is always `false`.

**Root cause** (verified): Both features call the client hook `useHasAcceptedIndexingAgreement(deploymentId)` (`packages/ui/src/subgraph/hooks/dips.hooks.ts:37`), which fetches the server route `pages/api/indexing-payments/has-accepted-agreement/[deployment].ts`. That route calls `indexingPaymentsSubgraphClient.subgraphDeploymentHasActiveIndexingAgreements(...)`, which **returns `false` without querying** unless the flag is on (`packages/shared/src/helpers/IndexingPaymentsSubgraph/client.ts:42-44`). The flag is `INDEXING_PAYMENTS_SUBGRAPH_ENABLED = process.env.INDEXING_PAYMENTS_SUBGRAPH_ENABLED === 'true'` (`packages/shared/src/helpers/env.ts:49`) — off by default for prod safety. `local-network/containers/ui/studio/ui.sh` exported neither `INDEXING_PAYMENTS_SUBGRAPH_ENABLED` nor `INDEXING_PAYMENTS_SUBGRAPH_URL`; `.env` carries only `INDEXING_PAYMENTS_SUBGRAPH_COMMIT` (an image-build pin, unrelated). So next-server's process had no flag → `undefined === 'true'` → `false` → short-circuit.

**Verified**:
- Before the fix, next-server (`/proc/<pid>/environ`) had no `INDEXING_PAYMENTS_*` vars (only `ENVIRONMENT=local`).
- The data and in-network path already worked: querying `http://studio-query-proxy:4002/query/1/indexing-payments/v0.1.0` from inside the `studio-ui` container returns two `state:Accepted` agreements (`subgraphDeploymentId` `0x61bfb535…47c1de` = `QmUvDoZbS7HJhqb4WzT51LkMDS4bSXWn7C3GfExE1vAjC1`, and `0xecfa1663…c283ff`). `studio-query-proxy` (compose service, `studio` profile) was up; the `shared/env.ts` default URL already points at it, so only the flag was missing.

**Repo**: `local-network` owns the fix — the subgraph-studio code is correct (the flag is intentionally off by default; prod enables it explicitly). No cross-repo PR needed.

**Fix (canonical, no hack)**: `local-network/containers/ui/studio/ui.sh`: `export INDEXING_PAYMENTS_SUBGRAPH_ENABLED=true` and `export INDEXING_PAYMENTS_SUBGRAPH_URL="http://studio-query-proxy:4002/query/1/indexing-payments/v0.1.0"` (explicit even though it matches the shared/env.ts default, for self-documentation). Recreate `studio-ui` so `ui.sh` re-runs (`next dev` reads env at launch; hot-reload doesn't pick up env changes).

**Verified after fix**: next-server env now has `INDEXING_PAYMENTS_SUBGRAPH_ENABLED=true` and the proxy URL on all next pids; `GET /studio/api/indexing-payments/has-accepted-agreement/0x61bfb535…47c1de/` → `{"hasAcceptedAgreement":true}` (HTTP 200), the all-zero control deployment → `{"hasAcceptedAgreement":false}`, and `/agreements/0x61bfb535…/` returns the real agreement record.

**PR**: not submitted. local-network `ui.sh` change committed to this repo.
