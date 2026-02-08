# Indexing Payments User Experience

**What changes when using Indexing Payments override?**

## TL;DR

- **Default:** TAP for query fees (no change)
- **With Override:** TAP + Indexing Payments (dipper service added)
- **Enable:** `docker compose -f docker-compose.yaml -f overrides/indexing-payments/docker-compose.yaml up`

## Key Differences

### Payment Methods

| Aspect | TAP (Default) | Indexing Payments (Override) |
|--------|---------------|------------------------------|
| **Use Case** | Query fees | Indexing fees |
| **Method** | Allocations + receipts | GRT transfers |
| **Capital** | $50-$1000 allocations | Minimal (just payment amount) |
| **Response** | Synchronous | Asynchronous (receipt ID) |
| **Burn** | No burn | 1% protocol burn |

### What's Added

**New Service:**
- `dipper` container running on ports 9000 (admin) and 9001 (indexer)

**New Database:**
- `dipper_1` database in postgres (unused in default setup)

**New Workflow:**
1. Admin registers indexing request
2. Indexer receives request via dipper
3. Indexer performs work, submits report
4. Dipper processes payment, returns receipt ID
5. Indexer polls receipt status (PENDING → SUBMITTED/FAILED)

### What Stays the Same

- All default services run unchanged
- TAP query fees continue working
- Graph node, gateway, indexer-agent unaffected
- Can switch back to default by stopping override

## Usage Comparison

**Default (TAP Only):**
```bash
docker compose up
# All services except dipper
```

**With Indexing Payments:**
```bash
docker compose -f docker-compose.yaml -f overrides/indexing-payments/docker-compose.yaml up
# All services including dipper
```

## Documentation

For detailed architecture and testing, see:
- [Architecture](../Architecture.md)
- [Testing Guide](../../../flows/IndexingPaymentsTesting.md)
- [Usage Guide](../../../overrides/indexing-payments/README.md)
