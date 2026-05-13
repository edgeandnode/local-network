---
name: send-indexing-request
description: Send a test indexing request to dipper via the CLI. Use when testing the DIPs flow end-to-end, when the user asks to register an indexing request, send a test agreement, trigger the DIPs pipeline, or test dipper proposals.
argument-hint: "[deployment_id]"
---

# Send Indexing Request

Register an indexing request with dipper and monitor the full DIPs pipeline: IISA candidate selection, RCA proposal signing, indexer-service accept/reject, and on-chain acceptance via the chain_listener.

## Targets

The dipper stack runs on the `lnet-test` VM. The `dipper-cli` Rust binary is built on the Mac (where the dipper repo lives) and stays Mac-side — no cross-compile or scp. To reach dipper's admin RPC at `:9000` from the Mac, open an SSH local-forward to the VM (it's exposed externally by compose, but a tunnel is the cleanest portable approach). Helper scripts in the local-network repo run on the VM via SSH.

For a local-only docker setup, drop the SSH wrappers and tunnel; everything else is identical.

## Steps

### 1. Build the dipper CLI (Mac)

Builds for the Mac's native arch — used as a client only, doesn't need to match the VM's arch.

```bash
cargo build --manifest-path /Users/samuel/Documents/github/dipper/Cargo.toml --bin dipper-cli --release
```

Always use the absolute path to the dipper repo and binary; never `cd` to the dipper repo, since later commands run from `/Users/samuel/Documents/github/local-network`.

### 2. Open an SSH tunnel to dipper's admin RPC

`dipper-cli` defaults to `http://localhost:9000`. The tunnel lets the Mac binary reach the VM's dipper without changing flags or hostnames. Idempotent — if it's already up, the second invocation is a no-op (port in use).

```bash
ssh -L 9000:localhost:9000 -fN lnet-test 2>/dev/null || true
```

Tear it down at the end of the session (or leave it; harmless idle).

### 3. Verify dipper is healthy (on the VM)

```bash
ssh lnet-test 'docker compose -f /home/mainuser/local-network/docker-compose.yaml ps dipper --format "{{.Status}}"'
```

Expect `Up ... (healthy)`. If not, run the `fresh-deploy` skill.

### 4. Ensure indexers have Redpanda query history

The IISA cronjob only scores indexers that have query history. Without it, scoring runs in degraded mode or excludes indexers the gateway hasn't routed to. Send queries through the gateway (which lives on the VM) to populate Redpanda for every indexer with allocations:

```bash
ssh lnet-test bash <<'REMOTE'
NETWORK_DEPLOYMENT=$(curl -s http://localhost:8000/subgraphs/name/graph-network \
  -H 'content-type: application/json' \
  -d '{"query":"{ _meta { deployment } }"}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['_meta']['deployment'])")
for i in $(seq 1 20); do
  curl -s "http://localhost:7700/api/deadbeefdeadbeefdeadbeefdeadbeef/deployments/id/${NETWORK_DEPLOYMENT}" \
    -H 'content-type: application/json' \
    -d '{"query":"{ _meta { block { number } } }"}' >/dev/null
done
REMOTE
```

Then trigger a fresh IISA scoring run on the VM:

```bash
ssh lnet-test 'cd /home/mainuser/local-network && docker compose run --rm iisa-cronjob' 2>&1 | tail -10
```

The cronjob runs once and exits. Exit codes: `0` success, `1` scoring/push failure, `2` missing push token. The last log line `Scoring complete: mode=..., indexers=N, ...` reports the outcome. The `indexers` count should equal the total number of indexers with allocations. If it's lower, send more queries and retry.

### 5. Send the indexing request (Mac binary, tunnelled to VM dipper)

If the skill was invoked with an argument (e.g. `/send-indexing-request QmSQq...`), use that as the deployment ID. Otherwise default to `QmPdbQaRCMhgouSZSW3sHZxU3M8KwcngWASvreAexzmmrh` (the graph-network subgraph).

Dipper's admin API is declarative: a single mutating method, `set-target-candidates`, takes the desired indexer count for a given `(deployment, chain)` tuple. The first call inserts a new request row; subsequent calls with a different `--num-candidates` value update it in place (grow or shrink). `--num-candidates 0` cancels. There is no separate `register`/`cancel` subcommand any more.

```bash
/Users/samuel/Documents/github/dipper/target/release/dipper-cli indexings set-target-candidates \
  --server-url http://localhost:9000 \
  --signing-key "0x2ee789a68207020b45607f5adb71933de0946baebbaaab74af7cbd69c8a90573" \
  <DEPLOYMENT_ID> \
  1337 \
  --num-candidates 3
```

`--num-candidates` is optional; omit it to let dipper use its configured maximum. Three is a sensible default for local testing — picks 3 of the 5 available indexers and exercises the full pipeline without saturating the stack.

The signing key belongs to RECEIVER (`0xf4EF6650E48d099a4972ea5B414daB86e1998Bd3`). Dipper's admin RPC allowlist only accepts this address; ACCOUNT0's key returns 403.

On success, the CLI prints a UUID — the indexing request ID.

To list available deployments to use a different one, query graph-node's status endpoint (also tunnel-friendly, but easier to ask graph-node directly via its container):

```bash
ssh lnet-test 'docker compose -f /home/mainuser/local-network/docker-compose.yaml exec graph-node \
  curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"query\":\"{ indexingStatuses { subgraph chains { network } } }\"}" \
  http://localhost:8030/graphql'
```

### 6. Monitor the pipeline (on the VM)

```bash
ssh lnet-test 'cd /home/mainuser/local-network && python3 scripts/monitor-dips-pipeline.py <REQUEST_ID>'
```

Polls dipper's postgres for status changes, checks the indexing-payments subgraph proactively, exits when all agreements reach a terminal state. Runtime: 30–120 s.

Tracks the full lifecycle: IISA candidate selection, RCA proposal delivery, indexer-service accept/reject, on-chain acceptance. If agreements stay in `CREATED` for >60 s, the script warns about the indexing-payments subgraph and may report it lagging or paused.

If the subgraph is paused (per the warning), resume it:

```bash
ssh lnet-test 'cd /home/mainuser/local-network && python3 scripts/check-subgraph-sync.py --resume indexing-payments'
```

Then re-run the monitor.

### 7. Check request status (Mac binary, tunnelled)

```bash
/Users/samuel/Documents/github/dipper/target/release/dipper-cli indexings status \
  --server-url http://localhost:9000 \
  --signing-key "0x2ee789a68207020b45607f5adb71933de0946baebbaaab74af7cbd69c8a90573" \
  <REQUEST_ID>
```

### 8. (Optional) Tear down the SSH tunnel

```bash
pkill -f "ssh -L 9000:localhost:9000.*lnet-test" 2>/dev/null || true
```

Leaving the tunnel open is also fine — it's a quiet idle connection.

## Reference

| Detail | Value |
|--------|-------|
| Admin RPC port | 9000 (tunnelled to localhost) |
| Indexer RPC port | 9001 (also exposed, not used by this skill) |
| Signing key | RECEIVER: `0x2ee789a68207020b45607f5adb71933de0946baebbaaab74af7cbd69c8a90573` |
| Signing address | `0xf4EF6650E48d099a4972ea5B414daB86e1998Bd3` |
| Chain ID | 1337 (hardhat) |
| Default deployment | `QmPdbQaRCMhgouSZSW3sHZxU3M8KwcngWASvreAexzmmrh` (graph-network; override via skill argument) |

## Common rejection reasons

- **OFFER_NOT_FOUND / OFFER_MISMATCH**: dipper successfully signed an RCA but the indexer-service can't find a matching on-chain offer. Most often means the indexing-payments subgraph hasn't indexed the offer yet. Wait a few seconds and re-monitor; if it persists, check the subgraph sync state.
- **PRICE_TOO_LOW**: dipper's pricing config doesn't meet the indexer-service's minimum. Compare `pricing_table` in `containers/indexing-payments/dipper/run.sh` with `min_grt_per_30_days` in the indexer-service config.
