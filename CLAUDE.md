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

Dev overrides (`compose/dev/dips.yaml`) mount local source for: contracts, indexer-rs, dipper, iisa, eligibility-oracle-node. Everything else uses pinned versions or clones at build time.

## Key Config

- `.environment` is the canonical config file. `.env` is a symlink to it.
- `COMPOSE_FILE=docker-compose.yaml:compose/dev/dips.yaml` activates dev overrides.
- `DOCKER_DEFAULT_PLATFORM=` must prefix docker compose commands to avoid conflicts with per-service `platform: linux/arm64` in dips.yaml. We are testing on MacOS, production on linux.

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
- When restarting containers that build from source, expect cargo build time. Don't assume instant restarts.
