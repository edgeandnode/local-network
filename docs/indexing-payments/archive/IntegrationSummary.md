# Indexing Payments Integration

**Status:** Phases 1-4 Complete ✅ | Blocked on dipper submodule access

## Quick Start

To enable Indexing Payments on local-network:

```bash
# Initialize dipper submodule (requires SSH access)
git submodule update --init dipper/source

# Start with override
docker compose -f docker-compose.yaml -f overrides/indexing-payments/docker-compose.yaml up
```

See [overrides/indexing-payments/README.md](../../overrides/indexing-payments/README.md) for usage.

## What Was Implemented

**Infrastructure (Phase 1):**
- Database: `dipper_1` created in postgres
- Environment: `DIPPER_ADMIN_RPC_PORT`, `DIPPER_INDEXER_RPC_PORT`
- Documentation: [docs/indexing-payments/](../indexing-payments/), [flows/](../../flows/)
- Scripts: merge-contracts, dipper-cli, test helpers

**Service Files (Phase 2):**
- [dipper/Dockerfile](../../dipper/Dockerfile) - Multi-stage Rust + Python build
- [dipper/run.sh](../../dipper/run.sh) - Configuration script
- Submodule: git@github.com:edgeandnode/dipper.git (main branch)

**Override (Phase 3):**
- [overrides/indexing-payments/docker-compose.yaml](../../overrides/indexing-payments/docker-compose.yaml)
- [overrides/indexing-payments/README.md](../../overrides/indexing-payments/README.md)
- [overrides/indexing-payments/start.sh](../../overrides/indexing-payments/start.sh)

**Documentation (Phase 4):**
- Updated [README.md](../../README.md) and [overrides/README.md](../../overrides/README.md)
- All terminology updated (DIPs → Indexing Payments)

## Current Blocker

**Dipper submodule not initialized** - requires access to private repo:
- `git@github.com:edgeandnode/dipper.git`
- Path: `dipper/source/` (empty)

Without submodule: cannot build dipper service, cannot test payment flows.

## Documentation

- [overrides/indexing-payments/README.md](../../../overrides/indexing-payments/README.md) - Usage guide
- [docs/indexing-payments/](../) - Architecture & implementation plans
- [flows/IndexingPaymentsTesting.md](../../../flows/IndexingPaymentsTesting.md) - Testing guide

## Next Steps

1. Initialize submodule: `git submodule update --init dipper/source`
2. Build: `docker compose -f docker-compose.yaml -f overrides/indexing-payments/docker-compose.yaml build`
3. Test: Follow [flows/IndexingPaymentsTesting.md](../../flows/IndexingPaymentsTesting.md)
