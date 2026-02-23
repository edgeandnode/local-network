# Indexing Payments Integration

ARCHIVED: This document describes the initial integration. Current setup uses published images (no submodules).

## Quick Start

To enable Indexing Payments on local-network:

```bash
# Enable indexing-payments profile in .env:
#   COMPOSE_PROFILES=indexing-payments
docker compose up
```

## What Was Implemented

**Infrastructure (Phase 1):**

- Database: `dipper_1` created in postgres
- Environment: `DIPPER_ADMIN_RPC_PORT`, `DIPPER_INDEXER_RPC_PORT`
- Documentation: [docs/indexing-payments/](../indexing-payments/), [docs/flows/](../../flows/)
- Scripts: merge-contracts, dipper-cli, test helpers

**Service Files (Phase 2):**

- [containers/indexing-payments/dipper/Dockerfile](../../../containers/indexing-payments/dipper/Dockerfile) - Wrapper image
- [containers/indexing-payments/dipper/run.sh](../../../containers/indexing-payments/dipper/run.sh) - Configuration script

**Override (Phase 3):**

- Service definitions in `docker-compose.yaml` with `profiles: [indexing-payments]`

**Documentation (Phase 4):**

- Updated [README.md](../../README.md)
- All terminology updated (DIPs → Indexing Payments)

## Notes

Dipper now uses a published image (`ghcr.io/edgeandnode/dipper-service`). No submodule required.

## Documentation

- Enable via `COMPOSE_PROFILES=indexing-payments` in `.env`
- [docs/indexing-payments/](../) - Architecture & implementation plans
- [docs/flows/IndexingPaymentsTesting.md](../../flows/IndexingPaymentsTesting.md) - Testing guide

## Next Steps

1. Build: `docker compose build dipper iisa-mock`
2. Test: Follow [docs/flows/IndexingPaymentsTesting.md](../../flows/IndexingPaymentsTesting.md)
