---
name: send-indexing-request
description: Send a test indexing request to dipper via the CLI. Use when testing the DIPs flow end-to-end, when the user asks to register an indexing request, send a test agreement, trigger the DIPs pipeline, or test dipper proposals.
argument-hint: "[deployment_id]"
---

# Send Indexing Request

Register an indexing request with dipper and monitor the full DIPs pipeline: IISA candidate selection, RCA proposal signing, indexer-service accept/reject, and on-chain acceptance via the chain_listener.

## Targets

The dipper stack runs on the `lnet-test` VM. Instead of building a `dipper-cli` binary on the Mac and tunnelling to the VM, run the **pinned `dipper-cli` GHCR image on the VM** with `docker run --rm --network host`. `--network host` lets the container reach dipper's admin RPC at `localhost:9000` on the VM host. The CLI image and the running dipper server share one pinned version (`DIPPER_VERSION` in `.env`), so the client always matches the server — no Mac build, no cross-compile, no version drift, no SSH tunnel.

For a local-only docker setup, drop the `ssh lnet-test` wrapper and run the same `docker run` directly; everything else is identical.

## Steps

### 1. Resolve the pinned dipper-cli image (on the VM)

The `dipper` server and the `dipper-cli` client both pin to `DIPPER_VERSION`, so the CLI image already present on the VM matches the running server. Confirm it's there:

```bash
ssh lnet-test 'docker images --format "{{.Repository}}:{{.Tag}}" | grep "^ghcr.io/edgeandnode/dipper-cli:"'
```

If it's missing (fresh machine), pull the tag matching the running dipper — `DIPPER_VERSION` in `.env`:

```bash
ssh lnet-test 'docker pull ghcr.io/edgeandnode/dipper-cli:<DIPPER_VERSION>'
```

The image entrypoint is `dipper-cli`, so every call is `docker run --rm --network host <image> <subcommand> ...`. The CLI invocations below resolve the image inline on the VM, so they stay correct across version bumps without a hardcoded tag.

### 2. Verify dipper is healthy (on the VM)

```bash
ssh lnet-test 'docker compose -f /home/mainuser/local-network/docker-compose.yaml ps dipper --format "{{.Status}}"'
```

Expect `Up ... (healthy)`. If not, run the `fresh-deploy` skill.

### 3. Ensure indexers have Redpanda query history

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

### 4. Send the indexing request (pinned CLI image on the VM)

If the skill was invoked with an argument (e.g. `/send-indexing-request QmSQq...`), use that as the deployment ID. Otherwise resolve the current graph-network deployment hash dynamically — it changes whenever the schema, ABI, or mapping does, so a hardcoded value goes stale on every contract rebuild and indexer-service then rejects the proposal with `SubgraphManifestUnavailable`:

```bash
DEPLOYMENT=$(ssh lnet-test 'curl -s http://localhost:8000/subgraphs/name/graph-network \
  -H "content-type: application/json" \
  -d "{\"query\":\"{ _meta { deployment } }\"}"' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['_meta']['deployment'])")
```

Dipper's admin API is declarative: a single mutating method, `set-target-candidates`, takes the desired indexer count for a given `(deployment, chain)` tuple. The first call inserts a new request row; subsequent calls with a different `--num-candidates` value update it in place (grow or shrink). `--num-candidates 0` cancels. There is no separate `register`/`cancel` subcommand any more.

```bash
ssh lnet-test 'docker run --rm --network host \
  $(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^ghcr.io/edgeandnode/dipper-cli:" | head -1) \
  indexings set-target-candidates \
  --server-url http://localhost:9000 \
  --signing-key "0x2ee789a68207020b45607f5adb71933de0946baebbaaab74af7cbd69c8a90573" \
  <DEPLOYMENT_ID> \
  1337 \
  --num-candidates 3'
```

The `$(...)` resolves the CLI image on the VM (inside the single-quoted remote command), so it never needs a hardcoded tag. `--num-candidates` is optional; omit it to let dipper use its configured maximum. Three is a sensible default for local testing — picks 3 of the available indexers and exercises the full pipeline without saturating the stack.

The signing key belongs to RECEIVER (`0xf4EF6650E48d099a4972ea5B414daB86e1998Bd3`). Dipper's admin RPC allowlist only accepts this address; ACCOUNT0's key returns 403.

On success, the CLI prints a UUID — the indexing request ID.

To list available deployments to use a different one, query graph-node's status endpoint:

```bash
ssh lnet-test 'docker compose -f /home/mainuser/local-network/docker-compose.yaml exec graph-node \
  curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"query\":\"{ indexingStatuses { subgraph chains { network } } }\"}" \
  http://localhost:8030/graphql'
```

### 5. Monitor the pipeline (on the VM)

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

### 6. Check request status (pinned CLI image on the VM)

```bash
ssh lnet-test 'docker run --rm --network host \
  $(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^ghcr.io/edgeandnode/dipper-cli:" | head -1) \
  indexings status \
  --server-url http://localhost:9000 \
  --signing-key "0x2ee789a68207020b45607f5adb71933de0946baebbaaab74af7cbd69c8a90573" \
  <REQUEST_ID>'
```

## Reference

| Detail | Value |
|--------|-------|
| Admin RPC port | 9000 (VM host port; the CLI container reaches it via `docker run --network host`) |
| Indexer RPC port | 9001 (also exposed, not used by this skill) |
| CLI image | `ghcr.io/edgeandnode/dipper-cli:${DIPPER_VERSION}` (pinned, matches the running dipper server) |
| Signing key | RECEIVER: `0x2ee789a68207020b45607f5adb71933de0946baebbaaab74af7cbd69c8a90573` |
| Signing address | `0xf4EF6650E48d099a4972ea5B414daB86e1998Bd3` |
| Chain ID | 1337 (hardhat) |
| Default deployment | Resolved dynamically from graph-network's `_meta.deployment` (override via skill argument) |

## Common rejection reasons

- **OFFER_NOT_FOUND / OFFER_MISMATCH**: dipper successfully signed an RCA but the indexer-service can't find a matching on-chain offer. Most often means the indexing-payments subgraph hasn't indexed the offer yet. Wait a few seconds and re-monitor; if it persists, check the subgraph sync state.
- **PRICE_TOO_LOW**: dipper's pricing config doesn't meet the indexer-service's minimum. Compare `pricing_table` in `containers/indexing-payments/dipper/run.sh` with `min_grt_per_30_days` in the indexer-service config.
