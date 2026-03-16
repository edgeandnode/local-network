---
name: send-indexing-request
description: Send a test indexing request to dipper via the CLI. Use when testing the DIPs flow end-to-end, when the user asks to register an indexing request, send a test agreement, trigger the DIPs pipeline, or test dipper proposals.
---

# Send Indexing Request

Register an indexing request with dipper and monitor the full DIPs pipeline: IISA candidate selection, RCA proposal signing, and indexer-service accept/reject.

## Steps

### 1. Build the dipper CLI (if not already built)

```bash
cd /Users/samuel/Documents/github/dipper && cargo build --bin dipper-cli --release
```

### 2. Verify dipper is healthy

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml ps dipper --format '{{.Status}}'
```

Should show `Up ... (healthy)`. If not, use the `fresh-deploy` skill first.

### 3. Ensure all indexers have Redpanda query history

The IISA cronjob only scores indexers that have query history in Redpanda. Without this, `compute_all_scores()` succeeds with a subset (only indexers the gateway has routed to), and the degraded fallback (which includes all indexers) never runs.

Send queries through the gateway to populate Redpanda for all indexers with allocations:

The gateway requires the API key in the URL path and uses deployment IDs, not subgraph names:

```bash
NETWORK_DEPLOYMENT=$(curl -s http://localhost:8000/subgraphs/name/graph-network \
  -H 'content-type: application/json' \
  -d '{"query":"{ _meta { deployment } }"}' | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['_meta']['deployment'])")

for i in $(seq 1 20); do
  curl -s "http://localhost:7700/api/deadbeefdeadbeefdeadbeefdeadbeef/deployments/id/${NETWORK_DEPLOYMENT}" \
    -H 'content-type: application/json' \
    -d '{"query":"{ _meta { block { number } } }"}' > /dev/null
done
```

Then trigger an IISA scoring run and verify all indexers are scored:

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml -f compose/extra-indexers.yaml \
  exec iisa-cronjob curl -s -X POST http://localhost:9090/run
```

Wait 10 seconds, then check the scoring log:

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml -f compose/extra-indexers.yaml \
  logs iisa-cronjob --since 15s 2>&1 | grep "Score computation complete"
```

The indexer count should match the total number of indexers with allocations. If it shows fewer, the gateway hasn't routed to all indexers yet -- send more queries and retry.

### 4. Send the indexing request

```bash
cd /Users/samuel/Documents/github/dipper && ./target/release/dipper-cli indexings register \
  --server-url http://localhost:9000 \
  --signing-key "0x2ee789a68207020b45607f5adb71933de0946baebbaaab74af7cbd69c8a90573" \
  QmPdbQaRCMhgouSZSW3sHZxU3M8KwcngWASvreAexzmmrh \
  1337
```

The signing key belongs to RECEIVER (`0xf4EF6650E48d099a4972ea5B414daB86e1998Bd3`). The admin RPC allowlist only accepts this address. ACCOUNT0's key will return 403.

On success, the CLI prints a UUID -- the indexing request ID.

To use a different deployment, query graph-node for available ones:

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml exec graph-node \
  curl -s -X POST -H "Content-Type: application/json" \
  -d '{"query":"{ indexingStatuses { subgraph chains { network } } }"}' \
  http://localhost:8030/graphql
```

### 5. Monitor the pipeline

Check logs from all three services involved in the flow:

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml logs -f dipper iisa indexer-service --since 30s 2>&1
```

The expected sequence:

1. **dipper** receives the request and calls IISA for candidate selection
2. **iisa** scores indexers and returns candidates (only 1 indexer in local-network)
3. **dipper** constructs an RCA, signs it via EIP-712, sends a proposal to indexer-service
4. **indexer-service** validates the RCA and accepts or rejects

### 6. Check request status

```bash
cd /Users/samuel/Documents/github/dipper && ./target/release/dipper-cli indexings status \
  --server-url http://localhost:9000 \
  --signing-key "0x2ee789a68207020b45607f5adb71933de0946baebbaaab74af7cbd69c8a90573" \
  <REQUEST_ID>
```

## Reference

| Detail | Value |
|--------|-------|
| Admin RPC port | 9000 |
| Signing key | RECEIVER: `0x2ee789a68207020b45607f5adb71933de0946baebbaaab74af7cbd69c8a90573` |
| Signing address | `0xf4EF6650E48d099a4972ea5B414daB86e1998Bd3` |
| Chain ID | 1337 (hardhat) |
| Default deployment | `QmPdbQaRCMhgouSZSW3sHZxU3M8KwcngWASvreAexzmmrh` |

## Common rejection reasons

- **SIGNER_NOT_AUTHORISED**: The payer (ACCOUNT0) isn't authorized as a signer on the RecurringCollector contract. The escrow manager authorizes signers on PaymentsEscrow (for TAP) but not on RecurringCollector.
- **PRICE_TOO_LOW**: Dipper's pricing config doesn't meet indexer-service's minimum. Compare `pricing_table` in dipper's run.sh with `min_grt_per_30_days` in indexer-service's config.
