---
name: send-indexing-request
description: Send a test indexing request to dipper via the CLI. Use when testing the DIPs flow end-to-end, when the user asks to register an indexing request, send a test agreement, trigger the DIPs pipeline, or test dipper proposals.
argument-hint: "[deployment_id]"
---

# Send Indexing Request

Register an indexing request with dipper and monitor the full DIPs pipeline: IISA candidate selection, RCA proposal signing, indexer-service accept/reject, and on-chain acceptance via the chain_listener.

## Targets

The dipper stack runs on the `lnet-test` VM. Both the trigger and the status check go through `scripts/dipper-cli.sh`, which runs the published `dipper-cli` image via `docker compose run --rm dipper-cli` — pinned in lockstep with the dipper server and pulled during `/fresh-deploy`, so there's no local clone or build. The compose service supplies the signing key and admin-RPC URL, so the wrapper just forwards your arguments. Helper scripts in the local-network repo also run on the VM via SSH.

For a local-only docker setup, drop the SSH wrappers; everything else is identical.

## Steps

### 1. Verify dipper is healthy (on the VM)

```bash
ssh lnet-test 'docker compose -f /home/mainuser/local-network/docker-compose.yaml ps dipper --format "{{.Status}}"'
```

Expect `Up ... (healthy)`. If not, run the `fresh-deploy` skill.

### 2. Ensure indexers have Redpanda query history

IISA is two services: `iisa` (the HTTP scoring API on `:8080`) and `iisa-scoring` (a continuous loop that reads the `gateway_queries` Redpanda topic and writes `indexer_scores.json` to a shared volume that `iisa` serves). The scoring loop only scores indexers that have query history. Without it, scoring runs in degraded mode or excludes indexers the gateway hasn't routed to. Send queries through the gateway (which lives on the VM) to populate Redpanda for every indexer with allocations:

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

`iisa-scoring` runs continuously (it re-scores every `IISA_SCORING_INTERVAL` seconds, 600 by default), so once the queries above land in Redpanda the next loop picks them up on its own. To force a fresh pass without waiting, restart it and watch its logs on the VM:

```bash
ssh lnet-test 'cd /home/mainuser/local-network && docker compose restart iisa-scoring && docker compose logs --tail 20 -f iisa-scoring' 2>&1 | tail -20
```

The loop writes `indexer_scores.json` to the volume that the `iisa` API reads. The log line reporting the scored indexer count should match the total number of indexers with allocations. If it's lower, send more queries and let the loop run again.

### 3. Send the indexing request (wrapper on the VM)

If the skill was invoked with an argument (e.g. `/send-indexing-request QmSQq...`), use that as the deployment ID. Otherwise resolve the current graph-network deployment hash dynamically — it changes whenever the schema, ABI, or mapping does, so a hardcoded value goes stale on every contract rebuild and indexer-service then rejects the proposal with `SubgraphManifestUnavailable`:

```bash
DEPLOYMENT=$(ssh lnet-test 'curl -s http://localhost:8000/subgraphs/name/graph-network \
  -H "content-type: application/json" \
  -d "{\"query\":\"{ _meta { deployment } }\"}"' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['_meta']['deployment'])")
```

The agreement is triggered through dipper's admin RPC, not the Redpanda `dips-signal.sh` path — dipper on this branch has no signal consumer that starts agreements, so producing to the `indexing-requirements` topic does nothing. The blessed trigger is the `scripts/dipper-cli.sh` wrapper, which sources the repo's env and signs with the correct key automatically.

Dipper's admin API is declarative: a single mutating method, `set-target-candidates`, takes the desired indexer count for a given `(deployment, chain)` tuple. The first call inserts a new request row; subsequent calls with a different `--num-candidates` value update it in place (grow or shrink). `--num-candidates 0` cancels. There is no separate `register`/`cancel` subcommand any more.

Run the wrapper on the VM — it runs the `dipper-cli` image on the compose network, reaching dipper by service name and signing with `INDEXER_SECRET` from the resolved env:

```bash
ssh lnet-test 'cd /home/mainuser/local-network && \
  scripts/dipper-cli.sh indexings set-target-candidates \
  <DEPLOYMENT_ID> \
  1337 \
  --num-candidates 3'
```

`--num-candidates` is optional; omit it to let dipper use its configured maximum. Three is a sensible default for local testing — picks 3 of the 5 available indexers and exercises the full pipeline without saturating the stack.

The wrapper signs with `INDEXER_SECRET`, which recovers to `INDEXER_ADDRESS` (`0xf4EF6650E48d099a4972ea5B414daB86e1998Bd3`) — the only address in dipper's `gateway_operator_allowlist`. Hardcoding a different key, or signing with an address that isn't `INDEXER_ADDRESS`, returns 403.

On success, the CLI prints a UUID — the indexing request ID.

To list available deployments to use a different one, query graph-node's status endpoint directly via its container:

```bash
ssh lnet-test 'docker compose -f /home/mainuser/local-network/docker-compose.yaml exec graph-node \
  curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"query\":\"{ indexingStatuses { subgraph chains { network } } }\"}" \
  http://localhost:8030/graphql'
```

### 4. Monitor the pipeline (on the VM)

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

### 5. Check request status (wrapper on the VM)

```bash
ssh lnet-test 'cd /home/mainuser/local-network && scripts/dipper-cli.sh indexings status <REQUEST_ID>'
```

## Reference

| Detail | Value |
|--------|-------|
| Admin RPC port | 9000 (`DIPPER_ADMIN_RPC_PORT`) |
| Indexer RPC port | 9001 (`DIPPER_INDEXER_RPC_PORT`, not used by this skill) |
| Signing key | `INDEXER_SECRET`: `0x2ee789a68207020b45607f5adb71933de0946baebbaaab74af7cbd69c8a90573` |
| Signing address | `INDEXER_ADDRESS`: `0xf4EF6650E48d099a4972ea5B414daB86e1998Bd3` (the only entry in dipper's `gateway_operator_allowlist`) |
| Chain ID | 1337 (hardhat) |
| Default deployment | Resolved dynamically from graph-network's `_meta.deployment` (override via skill argument) |

## Common rejection reasons

- **OFFER_NOT_FOUND / OFFER_MISMATCH**: dipper successfully signed an RCA but the indexer-service can't find a matching on-chain offer. Most often means the indexing-payments subgraph hasn't indexed the offer yet. Wait a few seconds and re-monitor; if it persists, check the subgraph sync state.
- **PRICE_TOO_LOW**: dipper's pricing config doesn't meet the indexer-service's minimum. Compare `pricing_table` in `containers/indexing-payments/dipper/run.sh` with `min_grt_per_30_days` in the indexer-service config.
