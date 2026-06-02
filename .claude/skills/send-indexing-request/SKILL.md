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

## Running in local mode (no VM/SSH)

When the whole stack runs in Docker on this machine, the VM/SSH wrapping above does not apply. Substitutions:

- **dipper repo / CLI**: the dipper repo is typically a sibling of local-network at `../dipper`. Confirm the actual location with the user before building (don't assume an absolute path). Build: `cargo build --manifest-path <dipper-repo>/Cargo.toml --bin dipper-cli --release`; binary at `<dipper-repo>/target/release/dipper-cli`. Never `cd` into the dipper repo — run from local-network with the manifest path.
- **Skip the SSH tunnel** — dipper admin RPC is directly at `http://localhost:9000` (a GET returns 405 = healthy JSON-RPC server).
- **No `ssh lnet-test` prefix** anywhere. Run `docker compose ...`, `curl`, and `python3 scripts/...` directly on the host from the local-network dir.
- **Ports (host)**: gateway `${GATEWAY_PORT}` (7700), graph-node GraphQL `:8000`, graph-node status `:8030`, IISA scores `http://localhost:8080/scores`, chain RPC `:8545`.
- **Health check**: `docker compose ps dipper --format "{{.Status}}"` (expect `Up ... (healthy)`).
- **num-candidates**: a fresh local stack has only the **primary indexer**. Use `--num-candidates 1` unless `/add-indexers` was run. IISA will only score indexers it has query history for, so the local default is 1.
- **Signing key** is the same RECEIVER key (`0x2ee789...`); ACCOUNT0's key returns 403 from the admin allowlist.

Everything in steps 1–8 below works locally with those substitutions (drop `ssh lnet-test`, use `../dipper/...` paths, no tunnel).

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

If the skill was invoked with an argument (e.g. `/send-indexing-request QmSQq...`), use that as the deployment ID. Otherwise resolve the current graph-network deployment hash dynamically — it changes whenever the schema, ABI, or mapping does, so a hardcoded value goes stale on every contract rebuild and indexer-service then rejects the proposal with `SubgraphManifestUnavailable`:

```bash
DEPLOYMENT=$(ssh lnet-test 'curl -s http://localhost:8000/subgraphs/name/graph-network \
  -H "content-type: application/json" \
  -d "{\"query\":\"{ _meta { deployment } }\"}"' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['_meta']['deployment'])")
```

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
| Default deployment | Resolved dynamically from graph-network's `_meta.deployment` (override via skill argument) |

## Common rejection reasons

- **OFFER_NOT_FOUND / OFFER_MISMATCH**: dipper successfully signed an RCA but the indexer-service can't find a matching on-chain offer. Most often means the indexing-payments subgraph hasn't indexed the offer yet. Wait a few seconds and re-monitor; if it persists, check the subgraph sync state.
- **PRICE_TOO_LOW**: dipper's pricing config doesn't meet the indexer-service's minimum. Compare `pricing_table` in `containers/indexing-payments/dipper/run.sh` with `min_grt_per_30_days` in the indexer-service config.

## Local-network troubleshooting

### Inspecting dipper state directly

dipper's postgres is the `postgres` service, database `dipper_1`. The agreements live in `dipper_reg_indexing_agreements`; `id` and `indexer_id` are `bytea` (use `encode(id,'hex')`). Status discriminants are **not** alphabetical — see the enum table in the repo `CLAUDE.md` (`-1`=Created, `5`=Expired, `6`=AcceptedOnChain, `7`=Rejected, etc.).

```bash
docker compose exec -T postgres psql -U postgres -d dipper_1 -c \
 "SELECT encode(id,'hex') id, status, COALESCE(rejection_reason,'-') reason, \
  CASE WHEN offer_tx_hash IS NULL OR offer_tx_hash='' THEN '-' ELSE 'yes' END offer, updated_at \
  FROM dipper_reg_indexing_agreements WHERE deployment_id='<DEPLOYMENT_ID>' ORDER BY created_at;"
```

A `monitor-dips-pipeline.py` timeout with the agreement stuck at `CREATED` (status -1) almost always means one of the next two.

### Stuck CREATED + chain frozen (nonce gap)

**Symptom**: agreement sits in CREATED to the deadline then Expired; `eth_blockNumber` (`:8545`) is frozen; dipper logs `Offer tx did not mine within receipt-poll window; treating as dropped` then `retry with fresh nonce` in a loop.

**Cause**: dipper signs offers with ACCOUNT0 (`0xf39F…2266`), shared with `tap_signer` + deploy scripts. A dropped/raced tx leaves dipper's local nonce ahead of chain; its only recovery is to bump *higher*, which orphans the missing nonce. On automine, nothing from that EOA can mine behind the gap → the whole chain freezes.

**Diagnose**:
```bash
RPC=http://localhost:8545; A0=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
curl -s -X POST -H 'content-type: application/json' -d '{"jsonrpc":"2.0","method":"txpool_status","params":[],"id":1}' $RPC        # queued > 0 = gap
curl -s -X POST -H 'content-type: application/json' -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getTransactionCount\",\"params\":[\"$A0\",\"pending\"],\"id\":1}" $RPC   # on-chain next nonce
```
Compare the on-chain nonce to the nonce in dipper's "Transaction sent" logs; the gap is the missing nonce(s). Inspect `txpool_content` to see exactly which nonces are stuck.

**One-shot unblock** (recovery, not a fix — the leak recurs on the next receipt timeout): send a 0-value ACCOUNT0 self-tx at the missing nonce to fill the gap so the queued offers mine.
```bash
cast send 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --value 0 --nonce <MISSING_NONCE> \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --rpc-url http://localhost:8545 --gas-limit 21000
```

### DEADLINE_EXPIRED on a healthy-looking proposal (chain-clock skew)

**Symptom**: indexer-service rejects with `DEADLINE_EXPIRED` immediately, even for a just-created agreement; the agreement's `terms.deadline` is in the *past* relative to wall clock.

**Cause**: dipper runs with `bypass_chain_clock_defenses=true` locally, so it anchors `terms.deadline = chain_listener_last_block_timestamp + deadline_seconds` (chain time), but indexer-service evaluates the deadline against **wall clock**. Hardhat block time only advances when it mines, so after any chain freeze/idle the chain clock lags wall clock. If that skew exceeds `deadline_seconds` (default 600), every proposal is born expired.

**Diagnose** — compare chain head timestamp to wall clock and watch the chain_listener lag:
```bash
curl -s -X POST -H 'content-type: application/json' -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}' http://localhost:8545 \
  | python3 -c "import json,sys,time; ts=int(json.load(sys.stdin)['result']['timestamp'],16); print('chain-head skew vs wall:', int(time.time())-ts,'s')"
docker logs dipper --since 90s 2>&1 | grep 'chain listener heartbeat' | tail -1   # subgraph_lag_seconds
```
**Fix**: let the chain catch up (it self-recovers as txs flow and blocks mine — skew shrinks back under 600s), or mine blocks to advance chain time. Durable mitigation for local testing: enable interval mining on Hardhat so block time tracks wall clock and this never recurs.

