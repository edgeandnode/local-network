---
name: studio-dips-e2e
description: Run the full Studio DIPs end-to-end test after a fresh deploy — seed a verified studio user, fund their wallet, deploy subgraphs into Studio, and drive a DIPs indexing request through to on-chain acceptance. Use when the user asks to "run the studio dips test", "test subgraph deployment + publishing + indexing", "exercise the studio DIPs flow", or wants a one-shot post-fresh-deploy smoke test of the Studio + DIPs pipeline.
argument-hint: "<wallet_address> [num_subgraphs]"
---

# Studio DIPs End-to-End Test

Exercise the whole Studio + DIPs path on the running stack in one pass:

1. seed a fully-verified studio User for a wallet address (no email confirmation),
2. fund that wallet with ETH on the local chain so it can publish from the UI,
3. deploy subgraphs into Studio for the user — the `indexing-payments` protocol subgraph plus N generic block-tracker test subgraphs (deployed to graph-node + seeded in Studio, **not** GNS-published),
4. prime IISA so the indexer is scorable,
5. send a DIPs indexing request for one of the deployed test subgraphs and monitor it through to `ACCEPTED_ON_CHAIN`,
6. verify the agreement landed in the `indexing-payments` subgraph, including the PR-15 `indexerInfo` URL link.

This is the sequence run manually after a `fresh-deploy`. It validates studio seeding, wallet funding, the deploy-router path, IISA scoring, and the dipper → indexer-service → chain_listener pipeline against a studio-deployed subgraph.

After the base flow passes, an **optional multi-indexer progression** (steps 7–9, below) adds extra indexers and exercises multi-candidate selection + per-indexer sync verification. The skill prompts the user before running it.

## Targets

Same topology as `fresh-deploy` and `send-indexing-request`: the stack runs on the `lnet-test` VM at `/home/mainuser/local-network`; the in-repo helper scripts run there via `ssh lnet-test 'cd /home/mainuser/local-network && ...'`. The `dipper-cli` Rust binary is built and run on the Mac (dipper repo is a sibling of local-network, e.g. `../dipper`) and reaches the VM's dipper admin RPC over an SSH local-forward on `:9000`.

For an all-local Docker stack (no VM): drop every `ssh lnet-test` wrapper and run the scripts directly from the local-network dir; dipper RPC is then directly on `localhost:9000` with no tunnel. Everything else is identical.

## Prerequisites

- A healthy stack with the **studio** and **indexing-payments** profiles enabled (this is the default on `nas/studio-dips-development`). Confirm dipper is healthy first; if not, run `fresh-deploy`.
  ```bash
  ssh lnet-test 'cd /home/mainuser/local-network && docker compose ps dipper --format "{{.Status}}"'   # expect Up ... (healthy)
  ```
- The studio services up (`studio-api`, `studio-ui`, `studio-query-proxy`, `studio-deployment-router`, `studio-redis`).
- A built `dipper-cli` on the Mac (step 4 builds it if missing).

## Arguments

- `wallet_address` (required) — the studio wallet to seed/fund/own the subgraphs (e.g. `0xAC7f6653186F4013fba9502236934c4156883240`).
- `num_subgraphs` (optional, default `5`) — how many generic `test-subgraph-N` deployments to seed.

Defaults used below: `ETH=10`, `CHAIN`=1337, signing key = RECEIVER (`0x2ee789…`), `--num-candidates` = number of indexers with allocations (1 on a fresh primary-only deploy; bump if `/add-indexers` was run).

## Steps

### 1. Seed the studio user + fund the wallet + mine

`seed-studio-user.sh` creates a verified User (email channel + confirmation pre-set) so the wallet can sign in via MetaMask and publish immediately. `fund-wallet.sh` uses `hardhat_setBalance` (sets the balance — a fresh wallet starts at `0x0`, so 10 ETH is "add 10"). Mine one block so the balance/state is visible to the next reads.

```bash
ADDR="<wallet_address>"
ssh lnet-test "cd /home/mainuser/local-network \
  && bash scripts/seed-studio-user.sh $ADDR \
  && bash scripts/fund-wallet.sh $ADDR 10 \
  && bash scripts/mine-block.sh 1"
# verify balance == 0x8ac7230489e80000 (10 ETH)
ssh lnet-test 'curl -s -X POST http://localhost:8545 -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"'"$ADDR"'\",\"latest\"],\"id\":1}"'
```

Idempotent: re-seeding an existing user is a no-op; re-funding just re-sets the balance.

### 2. Deploy subgraphs into Studio for the user

Two flavours, both via the deployment-router (creates the SubgraphVersion + graph-node aliases + playground/query-proxy routing). Neither publishes to GNS.

`deploy-studio-subgraph.py` surfaces an **already-deployed graph-node subgraph** (here the `indexing-payments` protocol subgraph) in the user's Studio account — handy for testing the Studio DIPs UI against a subgraph that will carry an agreement:

```bash
ssh lnet-test "cd /home/mainuser/local-network && python3 scripts/deploy-studio-subgraph.py $ADDR indexing-payments"
```

`deploy-studio-test-subgraphs.py` builds a minimal block-tracker subgraph **once** and seeds N unpublished `test-subgraph-1..N` (deterministic CIDs, vary only by startBlock). Needs node ≥ 20.18.1 + IPFS on the VM. Run in the background — the one-time `npm install` + `graph build` takes a few minutes:

```bash
ssh lnet-test "cd /home/mainuser/local-network && python3 scripts/deploy-studio-test-subgraphs.py $ADDR <num_subgraphs>"
```

Capture each printed `test-subgraph-N  sID  <CID>` line — you need one CID for step 5. `test-subgraph-1`'s CID is the default request target.

### 3. (Manual, optional) Publish from the Studio UI

The scripts deliberately stop at "deployed, not GNS-published". To exercise the on-chain GNS publish, the user signs in at `http://localhost:5000/studio/` with the funded wallet (via the SSH tunnel from `fresh-deploy`: `-L 5000/4000/7700/8545/8000`) and clicks Publish. After a UI publish, use the `index-published-subgraph` skill to signal + allocate so an indexer picks it up. This step is not required for the DIPs indexing-request test below, which operates on the deployment CID directly.

### 4. Build the dipper CLI + open the tunnel

```bash
cargo build --manifest-path ../dipper/Cargo.toml --bin dipper-cli --release   # fast no-op if already built
ssh -L 9000:localhost:9000 -fN lnet-test 2>/dev/null || true                   # idempotent
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:9000                 # 405 = healthy dipper RPC
```

### 5. Prime IISA, then send the indexing request

IISA only scores indexers with Redpanda query history; after a fresh deploy there's been no gateway traffic. Send a few gateway queries, then run a one-shot scoring pass. The final log line must read `Scoring complete: mode=..., indexers=N` with N = your indexer count.

```bash
# populate query history for indexers with allocations
ssh lnet-test bash <<'REMOTE'
ND=$(curl -s http://localhost:8000/subgraphs/name/graph-network -H 'content-type: application/json' \
  -d '{"query":"{ _meta { deployment } }"}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['_meta']['deployment'])")
for i in $(seq 1 20); do
  curl -s "http://localhost:7700/api/deadbeefdeadbeefdeadbeefdeadbeef/deployments/id/${ND}" \
    -H 'content-type: application/json' -d '{"query":"{ _meta { block { number } } }"}' >/dev/null
done
REMOTE
ssh lnet-test 'cd /home/mainuser/local-network && docker compose run --rm iisa-cronjob' 2>&1 | tail -3
```

Then register the request for a chosen `test-subgraph-N` CID (dipper's admin API is declarative — `set-target-candidates` upserts the desired indexer count; `--num-candidates 0` cancels). The signing key is RECEIVER; ACCOUNT0's key returns 403.

```bash
DEPLOYMENT="<test-subgraph-CID>"   # e.g. test-subgraph-1's CID from step 2
../dipper/target/release/dipper-cli indexings set-target-candidates \
  --server-url http://localhost:9000 \
  --signing-key "0x2ee789a68207020b45607f5adb71933de0946baebbaaab74af7cbd69c8a90573" \
  "$DEPLOYMENT" 1337 --num-candidates 1
# prints the request UUID
```

### 6. Monitor to on-chain acceptance + verify in the subgraph

```bash
ssh lnet-test 'cd /home/mainuser/local-network && python3 scripts/monitor-dips-pipeline.py <REQUEST_ID>'
```

Expect each agreement to go `CREATED → ACCEPTED_ON_CHAIN` (≈10s on hardhat for one indexer). Then confirm the `indexing-payments` subgraph (PR 15) indexed it, including the new `indexerInfo` URL link:

```bash
ssh lnet-test 'curl -s http://localhost:8000/subgraphs/name/indexing-payments -H "content-type: application/json" \
  --data "{\"query\":\"{ indexingAgreements(where:{subgraphDeploymentId_not:null}){ id indexer subgraphDeploymentId allocationId indexerInfo { url } } }\"}"'
```

A healthy result shows the agreement with `indexer`, the `subgraphDeploymentId` matching your chosen CID (hex-encoded), an `allocationId`, and `indexerInfo.url` resolved to the indexer's service URL.

## Pass criteria (base flow)

- Wallet balance == 10 ETH after step 1.
- `<num_subgraphs>/<num_subgraphs>` test subgraphs report `deployed`/`already deployed` in step 2.
- Step 5 IISA pass reports `indexers=N` equal to the indexer count.
- Step 6 monitor reports `accepted` with 0 failed, and the subgraph query returns the agreement with `indexerInfo.url` populated.

Once the base flow passes, **prompt the user** before going further: offer the optional multi-indexer progression below (e.g. via `AskUserQuestion`, or a plain "Base flow passed — want to exercise multi-indexer DIPs selection? It adds N extra indexers and sends a multi-candidate request"). Do **not** run steps 7–9 unprompted; stop here if the user declines.

## Optional progression: multi-indexer selection

Extends the single-indexer happy path to verify multi-candidate selection — dipper picking several indexers for one request, each accepting on-chain and indexing the deployment independently. Only run this after the user confirms.

### 7. Add extra indexers

A fresh deploy is primary-only (one indexer), so a multi-candidate request can't select more than one. Add extras with the `add-indexers` skill, which also scores them in IISA for you:

```
/add-indexers <N>      # e.g. 2 → indexers 2 and 3 (0x3c44…, 0x90f7…)
```

It brings up an isolated stack per extra, registers them on-chain, sets `always` rules so they allocate, drives query traffic to populate IISA history, and runs a scoring pass leaving `indexers = 1 + N`. Extras do **not** survive a `fresh-deploy` (the overlay is regenerated each time).

### 8. Send a multi-candidate request for a *different* test subgraph

Pick a different `test-subgraph-N` CID (so you don't collide with the base request's agreement) and request `--num-candidates` up to the indexer count. `/add-indexers` already left IISA scoring all indexers; if stale, re-run the priming block from step 5 first and confirm `indexers = 1 + N`.

```bash
DEPLOYMENT="<other-test-subgraph-CID>"   # e.g. test-subgraph-2's CID from step 2
../dipper/target/release/dipper-cli indexings set-target-candidates \
  --server-url http://localhost:9000 \
  --signing-key "0x2ee789a68207020b45607f5adb71933de0946baebbaaab74af7cbd69c8a90573" \
  "$DEPLOYMENT" 1337 --num-candidates <N>
# prints the request UUID, then monitor:
ssh lnet-test 'cd /home/mainuser/local-network && python3 scripts/monitor-dips-pipeline.py <REQUEST_ID>'
```

Expect `<N>` per-indexer lines each going `CREATED → ACCEPTED_ON_CHAIN`. dipper selects via IISA score, **not** a per-request allowlist — there is no CLI flag to pin specific indexers; `--num-candidates` only sets how many of the top-scored to take (so which indexers land is IISA's call). Confirm the agreements and their `indexerInfo.url` in the indexing-payments subgraph as in step 6 (query by `indexer` or order by `acceptedAtTx desc` — note the `subgraphDeploymentId` is the hex encoding of the CID, not the `Qm...` string).

### 9. Verify indexing progress on each selected indexer

Each indexer runs its own graph-node (`graph-node` for the primary, `graph-node-2`, `graph-node-3`, … for extras). Map a selected indexer to its graph-node by the suffix in its subgraph URL (`indexer-service-2:7601` → `graph-node-2`). Query each selected indexer's graph-node status for the deployment's `latestBlock` vs `chainHeadBlock`:

```bash
ssh lnet-test 'cd /home/mainuser/local-network
DEPL="<other-test-subgraph-CID>"
for gn in graph-node-2 graph-node-3; do   # the graph-nodes of the selected indexers
  echo "=== $gn ==="
  docker compose exec -T "$gn" curl -s -X POST http://localhost:8030/graphql \
    -H "content-type: application/json" \
    -d "{\"query\":\"{ indexingStatuses(subgraphs: [\\\"$DEPL\\\"]) { synced health chains { network latestBlock { number } chainHeadBlock { number } } } }\"}"
  echo
done'
```

A healthy result shows `synced: true` with `latestBlock == chainHeadBlock` (lag 0) on each — every selected indexer has independently indexed the deployment to the chain head.

### Optional-progression pass criteria

- Step 7 leaves `indexers = 1 + N` in the IISA scoring log.
- Step 8 monitor shows `<N>` agreements all reaching `ACCEPTED_ON_CHAIN`, each present in the indexing-payments subgraph with `indexerInfo.url` populated.
- Step 9 shows every selected indexer's graph-node `synced` with `latestBlock == chainHeadBlock`.

## Reference

| Detail | Value |
|--------|-------|
| Signing key (RECEIVER) | `0x2ee789a68207020b45607f5adb71933de0946baebbaaab74af7cbd69c8a90573` |
| Signing address | `0xf4EF6650E48d099a4972ea5B414daB86e1998Bd3` |
| Chain ID | 1337 (hardhat) |
| Studio UI (tunnelled) | `http://localhost:5000/studio/` |
| dipper admin RPC | `localhost:9000` (tunnelled) |
| Default ETH | 10 (`hardhat_setBalance`, = `0x8ac7230489e80000` wei) |
| Default num_subgraphs | 5 |

## Troubleshooting

- **No candidates selected / IISA `indexers=0`**: send more gateway queries (step 5) and re-run the cronjob; IISA won't score an indexer it has no query history for.
- **Agreement stuck `CREATED` → `Expired`, or `OFFER_NOT_FOUND` / `DEADLINE_EXPIRED`**: these are the dipper/chain-clock/nonce failure modes documented in the `send-indexing-request` skill's "Local-network troubleshooting" section — use those diagnostics (nonce-gap fill, chain-clock skew, subgraph resume) directly.
- **`num-candidates` > available indexers**: dipper can only fill up to the number of scored indexers. On a primary-only fresh deploy use `--num-candidates 1`; run `/add-indexers N` first to test multi-indexer selection.
