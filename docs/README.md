# Documentation

This directory contains detailed documentation for the local-network project.

## Indexing Payments

**[Start Here: indexing-payments/safe-based/README.md](./indexing-payments/safe-based/README.md)**

**Implementation Documentation:**

- [Architecture.md](./indexing-payments/safe-based/Architecture.md) - Technical architecture
- [DipperServicePlan.md](./indexing-payments/safe-based/DipperServicePlan.md) - Dipper service implementation
- [IndexerAgentPlan.md](./indexing-payments/safe-based/IndexerAgentPlan.md) - Agent modifications
- [IndexerServicePlan.md](./indexing-payments/safe-based/IndexerServicePlan.md) - Service updates

**Planning Summaries:** [archive/](./indexing-payments/archive/)

- [IntegrationSummary.md](./indexing-payments/archive/IntegrationSummary.md) - Implementation status & quick start
- [UserExperience.md](./indexing-payments/archive/UserExperience.md) - What changes with override
- [TestingStatus.md](./indexing-payments/archive/TestingStatus.md) - Current testing status

## Eligibility Oracle

**[Start Here: eligibility-oracle/Goal.md](./eligibility-oracle/Goal.md)**

- [Goal.md](./eligibility-oracle/Goal.md) - Objective and scope
- [Status.md](./eligibility-oracle/Status.md) - Implementation progress and log

## Test Plan Automation

**[Start Here: testing/reo/Goal.md](./testing/reo/Goal.md)**

- [Goal.md](./testing/reo/Goal.md) - Layered automation approach and workflow sequence
- [Status.md](./testing/reo/Status.md) - Progress, bugs found, and gaps
- [CurationSignal.md](./testing/reo/CurationSignal.md) - Task: add curation signal to local network setup
- [TestFramework.md](./testing/TestFramework.md) - Task: test framework evaluation (bash + Rust)

**Scripts:**

- `scripts/test-baseline-queries.sh` - Layer 0: Validate BaselineTestPlan GraphQL queries
- `scripts/test-indexer-guide-queries.sh` - Layer 0: Validate IndexerTestGuide queries and cast commands
- `scripts/test-baseline-state.sh` - Layer 1: Verify network state matches baseline expectations

## Graph Explorer

**[Start Here: explorer/Goal.md](./explorer/Goal.md)**

- [Goal.md](./explorer/Goal.md) - Task: integrate Graph Explorer with local network

## Testing Flows

Step-by-step testing guides: [flows/](./flows/)

- [EligibilityOracleTesting.md](./flows/EligibilityOracleTesting.md) - REO eligibility cycle
- [IndexingPaymentsTesting.md](./flows/IndexingPaymentsTesting.md) - Dipper indexing payments
- [IndexerAgentTesting.md](./flows/IndexerAgentTesting.md) - Indexer agent behavior

## Usage

**Service profiles** are enabled by default in `.env`. To customize, edit `COMPOSE_PROFILES`:

```bash
COMPOSE_PROFILES=rewards-eligibility,indexing-payments,block-oracle,explorer  # all (default)
COMPOSE_PROFILES=rewards-eligibility                                          # REO only
```

Then `docker compose up -d` applies the active profiles automatically.

## Documentation Guidelines

See [CLAUDE.md](../CLAUDE.md) for documentation standards including:

- File naming conventions (TitleCase for markdown)
- Directory organization (use subdirectories by topic)
- Linking and navigation (relative paths, cross-references)
- Content maintenance (update with code, archive or delete obsolete docs)
