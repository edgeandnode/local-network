# Local Network

A Docker Compose environment that runs the full Graph protocol stack locally for development and integration testing.

## Current Objective

Systematic end-to-end testing of DIPs (Direct Indexer Payments) before testnet deployment. Every bug found here must be fixed at the source with a proper PR to the relevant repo. No hack fixes, no workarounds that won't survive a fresh deployment.

When something breaks, document the root cause, identify which repo owns the fix, and describe what the PR should do. The goal is that testnet deployment encounters zero issues because every problem was already caught and patched here.

## Bug Tracking

When a bug is found during testing, log it in `BUGS.md` @BUGS.md with:

- What broke (symptom)
- Root cause
- Which repo needs the fix
- What the fix should be
- Whether a PR has been submitted

## Architecture

The stack has these layers:

- **Chain**: local anvil (Foundry) EVM node (chain ID 1337) with all Graph protocol contracts
- **Indexing**: graph-node, indexer-agent, indexer-service
- **Gateway**: routes paid queries to indexers
- **Payments (TAP)**: graph-tally-aggregator, graph-tally-escrow-manager, tap-agent
- **DIPs**: dipper (orchestrator), iisa (indexing indexer selection algorithm - subgraph-dips-indexer-selection)
- **Oracles**: block-oracle, eligibility-oracle-node (REO)

The stack runs entirely from pinned commits and images. The `graph-contracts` and `subgraph-deploy` images clone their respective sources at image-build time using the commit hashes pinned in `.env` (`CONTRACTS_COMMIT`, `NETWORK_SUBGRAPH_COMMIT`, `INDEXING_PAYMENTS_SUBGRAPH_COMMIT`); everything else pulls a tagged image from a registry.

## Key Config

- `.env` is the canonical config file (read by docker-compose, host scripts, and containers via volume mount at `/opt/config/.env`).
- `DOCKER_DEFAULT_PLATFORM=` must prefix docker compose commands on machines whose host arch differs from images (e.g. macOS arm64 hosts pulling linux/amd64 images).

## Dipper IndexingAgreement status enum

The dipper postgres `dipper_reg_indexing_agreements.status` column stores the discriminant values defined in `dipper-pgregistry/src/indexing_agreement.rs:160`. Six values are commonly observed in local-network. The discriminants are not contiguous and are easy to mis-map by intuition (in particular `6 = AcceptedOnChain` and `7 = Rejected` are not in alphabetical order). Always confirm against the source enum, not against natural ordering.

| Value | Variant | Meaning |
|---|---|---|
| -1 | Created | Inserted, proposal not yet attempted or in flight |
| 1 | DeliveryFailed | Terminal — proposal couldn't be delivered |
| 3 | CanceledByRequester | Terminal — payer cancelled |
| 4 | CanceledByIndexer | Terminal — indexer cancelled |
| 5 | Expired | Terminal — deadline passed before acceptance |
| 6 | AcceptedOnChain | `IndexingAgreementAccepted` event observed on-chain |
| 7 | Rejected | Off-chain rejection by indexer-service via gRPC |
| 8 | AbandonedByIndexer | Terminal — liveness checker saw no indexing progress; dipper cancelled and will reassign |

## DIPs conditions field

The audit-branch `RecurringCollectionAgreement` struct has a `uint16 conditions` field (a bitmask of payer-declared conditions like `CONDITION_ELIGIBILITY_CHECK = 1`). Local-network always uses `conditions = 0`. Setting any non-zero value makes the `RecurringCollector` contract staticcall the payer to verify it implements an eligibility callback interface. The on-chain payer is the `RecurringAgreementManager` contract, not an EOA: as of dipper PR #643 (the `upgrade` branch, which is what local-network currently pins via `DIPPER_VERSION`), dipper routes every offer through the manager via `offer_via_manager()` instead of paying from a wallet directly. Dipper's own wallet still signs and sends the transaction under a manager role, but it is not the payer. Whether a non-zero `conditions` bit works therefore depends on whether the `RecurringAgreementManager` implements the eligibility callback interface — this has not been verified, so keep `conditions = 0` unless that path is explicitly checked.

## On-chain Event Signatures

Each topic0 below maps to exactly one event. An earlier version of this table mislabeled the collection events as allocation/start events; the mappings here were corrected by recomputing every keccak and cross-checking live `eth_getLogs`. The real subtlety is that both a DIPs acceptance and a rewards collection are `multicall` transactions (selector `0xac9650d8`) that bundle several inner calls, so a single tx emits several of these events at once. Decode the inner multicall selectors or check the agent logs to tell which operation a tx performed -- don't infer it from one topic0 alone. SubgraphService is at `0xcf7ed3...` on local-network.

| topic0 prefix | Event | Emitted by |
|---|---|---|
| `0x443f56bd` | IndexingRewardsCollected | SubgraphService `collect` (during `presentPOI`, indexing-rewards collection) |
| `0x02a24054` | POIPresented | SubgraphService `collect` |
| `0x54fe682b` | ServicePaymentCollected | SubgraphService `collect` |
| `0xd3803eb8` | ServiceStarted | `startService` (and the DIPs `acceptIndexingAgreement` multicall) |
| `0xe5e185fa` | AllocationCreated | `startService` (and the DIPs `acceptIndexingAgreement` multicall) |
| `0xddf252ad` | Transfer | GRT token operations |
| `0x8c5be1e5` | Approval | GRT token operations |
| `0xa111914d` | HorizonRewardsAssigned | RewardsManager |
| `0x48c384dd` | HorizonStakeDeposited | HorizonStaking |
| `0xeaf6ea3a` | ProvisionIncreased | HorizonStaking |

To distinguish a DIPs acceptance from a rewards collection: a DIPs acceptance bundles `startService` + `acceptIndexingAgreement`, so its tx carries the start/allocation events (`ServiceStarted`, `AllocationCreated`) plus `IndexingAgreementAccepted`; a rewards collection carries the `IndexingRewardsCollected` / `POIPresented` / `ServicePaymentCollected` group instead. Decode the inner multicall selectors, or check the agent log for a `proposalId` field, to confirm.

## Rules

- Never apply hack fixes to unblock testing. If something is broken, find the root cause and document it properly in bugs.
- Every fix that touches another repo (dipper, indexer-rs, contracts, iisa, etc.) needs a PR to that repo.
- Fixes to local-network config/scripts should be committed to this repo.
