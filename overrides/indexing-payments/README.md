# Indexing Payments Override

This override adds the dipper service for Indexing Payments, enabling indexers to receive payments for indexing work via GRT transfers.

## What Are Indexing Payments?

Indexing Payments solve capital efficiency problems for indexing fees:

- **No large allocations needed** ($50-$1000 for $5-$100 monthly fees)
- **GRT transfers** without allocation overhead
- **Asynchronous processing** with receipt IDs
- **1% protocol burn** automatically applied

See [../../docs/indexing-payments/README.md](../../docs/indexing-payments/README.md) for architecture details.

## Payment Systems

| System                       | Use Case      | Method                 |
| ---------------------------- | ------------- | ---------------------- |
| **TAP** (default)            | Query fees    | Allocations + receipts |
| **Payments** (this override) | Indexing fees | GRT transfers          |

Both systems can run simultaneously and are independent.

## Prerequisites

1. **Dipper source repository** cloned:
   ```bash
   git submodule update --init --recursive dipper/source
   ```

## Usage

### Start with Indexing Payments

```bash
# Build (first time or after changes)
docker compose -f docker-compose.yaml -f overrides/indexing-payments/docker-compose.yaml build

# Start all services including dipper
docker compose -f docker-compose.yaml -f overrides/indexing-payments/docker-compose.yaml up -d

# Or use helper script
./overrides/indexing-payments/start.sh
```

### Verify Services

```bash
# Check all services
docker compose ps

# Check dipper specifically
docker compose logs dipper

# Check database
docker compose exec postgres psql -U postgres -l | grep dipper
```

### Test Functionality

See [../../flows/IndexingPaymentsTesting.md](../../flows/IndexingPaymentsTesting.md) for step-by-step testing guide.

### Stop Indexing Payments

```bash
# Stop all services
docker compose -f docker-compose.yaml -f overrides/indexing-payments/docker-compose.yaml down

# Or just stop dipper
docker compose stop dipper
docker compose rm dipper
```

## Configuration

The dipper service is configured via `dipper/run.sh` which generates a config file at runtime using environment variables from `.env`.

**Key configuration:**

- **Admin RPC:** `localhost:${DIPPER_ADMIN_RPC_PORT}` (default: 9000)
- **Indexer RPC:** `localhost:${DIPPER_INDEXER_RPC_PORT}` (default: 9001)
- **Database:** `postgres://postgres:postgres@postgres:5432/dipper_1`
- **Network:** Queries network subgraph via gateway
- **Signer:** Uses `ACCOUNT0_SECRET` for transaction signing

## Troubleshooting

**Dipper fails to start:**

- Verify submodule: `ls dipper/source/`
- Check logs: `docker compose logs dipper`

**Database connection errors:**

- Ensure postgres is healthy: `docker compose ps postgres`
- Check database exists: `docker compose exec postgres psql -U postgres -l | grep dipper`

**RPC endpoints not responding:**

- Check port conflicts: `lsof -i :9000` and `lsof -i :9001`
- Verify ports in `.env` match docker-compose

**Contracts not found:**

- Verify contracts deployed: `docker compose logs graph-contracts`

## Switching Back to Default

Simply stop using the override:

```bash
# Stop everything
docker compose -f docker-compose.yaml -f overrides/indexing-payments/docker-compose.yaml down

# Start without indexing payments
docker compose up -d
```

The dipper database remains but is unused.
