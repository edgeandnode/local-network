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

- **Chain**: local Hardhat EVM node (chain ID 1337) with all Graph protocol contracts
- **Indexing**: graph-node, indexer-agent, indexer-service
- **Gateway**: routes paid queries to indexers
- **Payments (TAP)**: tap-aggregator, tap-escrow-manager, tap-agent
- **DIPs**: dipper (orchestrator), iisa (indexing indexer selection algorithm - subgraph-dips-indexer-selection)
- **Oracles**: block-oracle, eligibility-oracle-node (REO)

The stack runs entirely from pinned commits and images. The `graph-contracts` and `subgraph-deploy` images clone their respective sources at image-build time using the commit hashes pinned in `.env` (`CONTRACTS_COMMIT`, `NETWORK_SUBGRAPH_COMMIT`, `INDEXING_PAYMENTS_SUBGRAPH_COMMIT`); everything else pulls a tagged image from a registry.

## Key Config

- `.env` is the canonical config file (read by docker-compose, host scripts, and containers via volume mount at `/opt/config/.env`).
- `DOCKER_DEFAULT_PLATFORM=` must prefix docker compose commands on machines whose host arch differs from images (e.g. macOS arm64 hosts pulling linux/amd64 images).

## Dipper IndexingAgreement status enum

The dipper postgres `dipper_reg_indexing_agreements.status` column stores the discriminant values defined in `dipper-pgregistry/src/indexing_agreement.rs:131`. Six values are commonly observed in local-network. The discriminants are not contiguous and are easy to mis-map by intuition (in particular `6 = AcceptedOnChain` and `7 = Rejected` are not in alphabetical order). Always confirm against the source enum, not against natural ordering.

| Value | Variant | Meaning |
|---|---|---|
| -1 | Created | Inserted, proposal not yet attempted or in flight |
| 1 | DeliveryFailed | Terminal — proposal couldn't be delivered |
| 3 | CanceledByRequester | Terminal — payer cancelled |
| 4 | CanceledByIndexer | Terminal — indexer cancelled |
| 5 | Expired | Terminal — deadline passed before acceptance |
| 6 | AcceptedOnChain | `IndexingAgreementAccepted` event observed on-chain |
| 7 | Rejected | Off-chain rejection by indexer-service via gRPC |

## DIPs conditions field

The audit-branch `RecurringCollectionAgreement` struct has a `uint16 conditions` field (a bitmask of payer-declared conditions like `CONDITION_ELIGIBILITY_CHECK = 1`). Local-network always uses `conditions = 0`. Setting any non-zero value makes the `RecurringCollector` contract staticcall the payer to verify it implements an eligibility callback interface. Our payer is an EOA (ACCOUNT0 = dipper's wallet), so any non-zero condition bit causes both the `offer()` and `accept()` calls to revert. Exercising the eligibility-check path requires a contract payer, which is out of scope for local testing.

## On-chain Event Signatures

The SubgraphService contract (`0xcf7ed3...` on local-network) emits events that share topic0 across different functions. Never assume a topic0 maps to a single function -- always cross-reference with the transaction's input selector or agent logs.

| topic0 prefix | Event | Emitted by |
|---|---|---|
| `0x443f56bd` | Allocation-related | **Both** `startService` and `acceptIndexingAgreement` -- ambiguous without checking tx selector |
| `0x02a24054` | AllocationCreated | `startService` |
| `0x54fe682b` | ServiceStarted | `startService` |
| `0xddf252ad` | Transfer | GRT token operations |
| `0x8c5be1e5` | Approval | GRT token operations |
| `0xa111914d` | RewardsAssigned | RewardsManager |
| `0x48c384dd` | ProvisionIncreased | HorizonStaking |
| `0xeaf6ea3a` | TokensAllocated | HorizonStaking |

To distinguish a DIPs acceptance from a regular allocation: check the agent log for a `proposalId` field, or check the tx input for the `acceptIndexingAgreement` function selector vs `startService`.

## Rules

- Never apply hack fixes to unblock testing. If something is broken, find the root cause and document it properly in bugs.
- Every fix that touches another repo (dipper, indexer-rs, contracts, iisa, etc.) needs a PR to that repo.
- Fixes to local-network config/scripts should be committed to this repo.
