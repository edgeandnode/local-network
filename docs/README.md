# Documentation

This directory contains detailed documentation for the local-network project.

## Indexing Payments

**[Start Here: indexing-payments/README.md](./indexing-payments/README.md)**

**Implementation Documentation:**
- [Architecture.md](./indexing-payments/Architecture.md) - Technical architecture
- [DipperServicePlan.md](./indexing-payments/DipperServicePlan.md) - Dipper service implementation
- [IndexerAgentPlan.md](./indexing-payments/IndexerAgentPlan.md) - Agent modifications
- [IndexerServicePlan.md](./indexing-payments/IndexerServicePlan.md) - Service updates

**Planning Summaries:** [archive/](./indexing-payments/archive/)
- [IntegrationSummary.md](./indexing-payments/archive/IntegrationSummary.md) - Implementation status & quick start
- [UserExperience.md](./indexing-payments/archive/UserExperience.md) - What changes with override
- [TestingStatus.md](./indexing-payments/archive/TestingStatus.md) - Current testing status

## Usage

**To enable Indexing Payments:**
```bash
docker compose -f docker-compose.yaml -f overrides/indexing-payments/docker-compose.yaml up
```

See [overrides/indexing-payments/README.md](../overrides/indexing-payments/README.md) for usage guide and [flows/IndexingPaymentsTesting.md](../flows/IndexingPaymentsTesting.md) for testing.

## Documentation Guidelines

See [CLAUDE.md](../CLAUDE.md) for documentation standards including:

- File naming conventions (TitleCase for markdown)
- Directory organization (use subdirectories by topic)
- Linking and navigation (relative paths, cross-references)
- Content maintenance (update with code, archive or delete obsolete docs)
