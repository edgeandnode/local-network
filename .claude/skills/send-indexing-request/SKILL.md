---
name: send-indexing-request
description: Send a test indexing request to dipper via the CLI. Use when testing the DIPs flow end-to-end, when the user asks to register an indexing request, send a test agreement, trigger the DIPs pipeline, or test dipper proposals.
argument-hint: "[deployment_id]"
---

# Send Indexing Request

Register an indexing request with dipper and monitor the full DIPs pipeline: IISA candidate selection, RCA proposal signing, indexer-service accept/reject, and on-chain acceptance via the chain_listener.

## Steps

### 1. Build the dipper CLI (if not already built)

```bash
cargo build --manifest-path /Users/samuel/Documents/github/dipper/Cargo.toml --bin dipper-cli --release
```

The path comes from `DIPPER_SOURCE_ROOT` in `.environment`. Always use absolute paths to the dipper binary -- never `cd` to the dipper repo, as it breaks subsequent docker compose commands that expect to be in the local-network directory.

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

If this skill was invoked with an argument (e.g., `/send-indexing-request QmSQq...`), use that value as the deployment ID. Otherwise default to `QmPdbQaRCMhgouSZSW3sHZxU3M8KwcngWASvreAexzmmrh` (the graph-network subgraph).

```bash
/Users/samuel/Documents/github/dipper/target/release/dipper-cli indexings register \
  --server-url http://localhost:9000 \
  --signing-key "0x2ee789a68207020b45607f5adb71933de0946baebbaaab74af7cbd69c8a90573" \
  <DEPLOYMENT_ID> \
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

```bash
python3 scripts/monitor-dips-pipeline.py <REQUEST_ID>
```

This polls dipper's database for agreement status changes, checks indexing-payments subgraph health proactively, and exits when all agreements reach a terminal state. Expected runtime: 30-120 seconds.

The script tracks the full lifecycle: IISA candidate selection, RCA proposal delivery, indexer-service accept/reject, and on-chain acceptance via dipper's chain_listener. If agreements stay in `CREATED` for >60 seconds, it checks the indexing-payments subgraph and warns if it is lagging or paused (BUG-014).

If the script warns about the indexing-payments subgraph, resume it:

```bash
python3 scripts/check-subgraph-sync.py --resume indexing-payments
```

Then re-run the monitor.

### 6. Check request status

```bash
/Users/samuel/Documents/github/dipper/target/release/dipper-cli indexings status \
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
| Default deployment | `QmPdbQaRCMhgouSZSW3sHZxU3M8KwcngWASvreAexzmmrh` (graph-network; override via skill argument) |

## Common rejection reasons

- **SIGNER_NOT_AUTHORISED**: The payer (ACCOUNT0) isn't authorized as a signer on the RecurringCollector contract. The escrow manager authorizes signers on PaymentsEscrow (for TAP) but not on RecurringCollector.
- **PRICE_TOO_LOW**: Dipper's pricing config doesn't meet indexer-service's minimum. Compare `pricing_table` in dipper's run.sh with `min_grt_per_30_days` in indexer-service's config.
