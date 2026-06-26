---
name: add-indexers
description: Add N extra indexers to the running local-network stack. Use when the user asks to add indexers, spin up another indexer, get more indexers up, bring up new indexers, or wants extra indexers for testing. Also trigger when the user says a number followed by 'indexers' (e.g. 'add 3 indexers', 'spin up 2 more').
argument-hint: "[count]"
allowed-tools:
  - Bash
  - Read
  - Grep
---

# Add Extra Indexers

Add N extra indexers to the running local network. Each extra gets a fully isolated stack (its own postgres, graph-node, indexer-agent, indexer-service, tap-agent) and uses the **same Docker image as the primary** for every service — built from the same `containers/...` Dockerfile contexts, parameterized at runtime via per-extra `environment:` overrides for indexer identity and hostnames. Protocol subgraphs (network, epoch, indexing-payments) are read from the primary graph-node; extras only handle their own indexing work.

The argument is the number of NEW indexers to add (defaults to 1).

## Targets

This skill assumes the docker stack runs on a remote VM (`lnet-test` here) and Claude executes from the Mac. Concretely:

- The generator script (`scripts/gen-extra-indexers.py`) runs on the **Mac**, because it imports `eth_account` / `mnemonic` and the VM's stripped-down system Python lacks both pip and those packages.
- The generator writes `compose/extra-indexers.yaml` and updates `.env`'s `COMPOSE_FILE` entry on the **Mac**. Both must be `scp`'d to the VM before any `docker compose` command runs there.
- Every `docker compose ...`, `docker ps`, `docker pause/unpause`, and any `curl http://localhost:...` against a stack service must run on the **VM** via `ssh lnet-test '...'`.

For a local-only docker setup (everything on Mac), drop the `ssh lnet-test` wrappers and skip the `scp` steps. Everything else is identical.

Mac path: `/Users/samuel/Documents/github/local-network`. VM path: `/home/mainuser/local-network`. Adjust both if your layout differs.

## Accounts

Extras use hardhat "junk" mnemonic accounts starting at index 2. Maximum 18 extra (indices 2–19). Each indexer also gets a unique operator derived from a mnemonic of the form `test test test ... test {bip39_word}` (11 "test" + 1 valid checksum word). The generator handles mnemonic validation, operator derivation, ETH funding, and on-chain `setOperator` for both `SubgraphService` and `HorizonStaking`.

| Suffix | Mnemonic Index | Address |
|--------|---------------|---------|
| 2 | 2 | 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC |
| 3 | 3 | 0x90F79bf6EB2c4f870365E785982E1f101E93b906 |
| 4 | 4 | 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65 |
| 5 | 5 | 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc |

## Steps

### 1. Determine current extra count (on the VM)

```bash
ssh lnet-test 'docker ps --format "{{.Names}}" | grep "indexer-agent-" | sed "s/indexer-agent-//" | sort -n | tail -1'
```

Empty output → current extras = 0. Otherwise the highest suffix minus 1 is the count (suffix 2 = 1 extra, suffix 3 = 2 extras, etc.).

### 2. Calculate new total

`new_total = current_count + requested`. Cap at 18; warn if the user asks for more than the available slots.

### 3. Generate compose yaml on the Mac, sync to VM

```bash
cd /Users/samuel/Documents/github/local-network
python3 scripts/gen-extra-indexers.py <NEW_TOTAL>
```

This (re)generates `compose/extra-indexers.yaml` for **all** extras (existing + new — idempotent) and updates the `COMPOSE_FILE` line in `.env` to include the path. Both files then need to land on the VM:

```bash
scp /Users/samuel/Documents/github/local-network/compose/extra-indexers.yaml \
    lnet-test:/home/mainuser/local-network/compose/extra-indexers.yaml
scp /Users/samuel/Documents/github/local-network/.env \
    lnet-test:/home/mainuser/local-network/.env
```

After the scp, `ssh lnet-test 'cd /home/mainuser/local-network && docker compose config --services'` should list the new `*-N` services alongside the primary ones.

### 4. Register new indexers on-chain

The `start-indexing-extra` one-shot stakes GRT and authorizes operators for every extra in the YAML.

```bash
ssh lnet-test 'cd /home/mainuser/local-network && docker compose run --rm start-indexing-extra'
```

Watch for `All extra indexers registered` near the end of the output — that's the success signal. The container exits 0.

### 5. Bring up the new containers

`--no-deps` prevents compose from walking the dependency tree (which would bounce shared services like `chain` or `gateway`). `--no-recreate` leaves already-running containers alone. Pass every new service explicitly so compose doesn't accidentally start something else.

```bash
ssh lnet-test 'cd /home/mainuser/local-network && docker compose up -d --no-deps --no-recreate \
  postgres-2 graph-node-2 indexer-agent-2 indexer-service-2 tap-agent-2 \
  postgres-3 graph-node-3 indexer-agent-3 indexer-service-3 tap-agent-3 \
  ...'
```

Substitute the actual service names for the suffixes you're adding.

### 6. Wait for the new containers to be healthy

Each extra's image is the same as the primary's — built once, reused by all extras of that role. After step 5, only the postgres / graph-node / indexer-agent / indexer-service / tap-agent containers themselves need to start (no Rust compile, no source mount, no flock build pass). They typically reach `healthy` within ~30 seconds.

```bash
EXPECTED=N  # number of total extras (existing + new)
while true; do
  HEALTHY=$(ssh lnet-test 'docker ps --format "{{.Names}} {{.Status}}"' \
    | grep -E '(indexer-agent|indexer-service)-[0-9]' | grep -c healthy)
  echo "$HEALTHY / $((EXPECTED * 2)) agent+service healthy"
  [ "$HEALTHY" -ge "$((EXPECTED * 2))" ] && break
  sleep 5
done
```

### 7. Wait for the network subgraph to index URL registrations

When each new indexer-agent starts, it calls `subgraphService.register(url, geo)` on-chain. The primary's network subgraph must index that event before IISA or dipper can see the new indexer. Curls hit the primary graph-node on the VM:

```bash
TOTAL_EXPECTED=$((1 + N))   # primary + extras
while true; do
  COUNT=$(ssh lnet-test 'curl -s -X POST -H "Content-Type: application/json" \
    -d "{\"query\":\"{ indexers(where: { url_not: \\\"\\\" }) { id } }\"}" \
    http://localhost:8000/subgraphs/name/graph-network' \
    | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']['indexers']))")
  echo "$COUNT / $TOTAL_EXPECTED indexers with URLs"
  [ "$COUNT" -ge "$TOTAL_EXPECTED" ] && break
  sleep 5
done
```

### 8. Set `always` indexing rules on each extra agent

Without an explicit rule, extras allocate to nothing, so the gateway never routes queries to them, the IISA cronjob excludes them from scoring (no Redpanda history), and indexer-2+ become invisible to the rest of the stack. Fix it by setting an `always` rule on each extra's indexer-management API.

Each extra's management port maps to host `17600 + suffix * 10` (suffix 2 → 17620, suffix 3 → 17630, etc.). The indexer-management API listens on `7600` inside the container.

Fetch the network-subgraph deployment ID (it changes whenever the schema does), then mutate the rule on each extra:

```bash
ssh lnet-test bash <<'REMOTE'
NETWORK_DEPLOYMENT=$(curl -s http://localhost:8000/subgraphs/name/graph-network \
  -H 'content-type: application/json' \
  -d '{"query":"{ _meta { deployment } }"}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['_meta']['deployment'])")
echo "network deployment: $NETWORK_DEPLOYMENT"

for port in 17620 17630 17640 17650; do  # adjust to the actual suffixes you brought up
  curl -s "http://localhost:$port/" \
    -H 'content-type: application/json' \
    -d "{\"query\":\"mutation setIndexingRule(\$rule: IndexingRuleInput!) { setIndexingRule(identifier: \\\"$NETWORK_DEPLOYMENT\\\", rule: \$rule) { identifier decisionBasis } }\",
         \"variables\": { \"rule\": { \"identifier\": \"$NETWORK_DEPLOYMENT\", \"identifierType\": \"deployment\", \"allocationAmount\": \"1000000000000000000\", \"decisionBasis\": \"always\", \"protocolNetwork\": \"eip155:1337\" } }}"
  echo
done
REMOTE
```

Each agent's reconciliation loop fires roughly every 15 seconds in local-dev mode, so allocations land within ~30 seconds.

### 9. Poll for allocations, then drive query traffic to the extras

The gateway's candidate-selection algorithm strongly favors the highest-staked indexer (= primary). Without intervention, extras get no queries and IISA scores them with no data. Workaround: pause the primary's `indexer-service` briefly so gateway routes to extras, then unpause.

Before pausing, set an offchain rule on the primary's agent to protect the `indexing-payments` subgraph (without this the agent will mark indexing-payments unhealthy when it sees the paused service and pause the subgraph; reconciliation re-pauses it on resume because there's no offchain rule to override).

```bash
ssh lnet-test bash <<'REMOTE'
NETWORK_DEPLOYMENT=$(curl -s http://localhost:8000/subgraphs/name/graph-network \
  -H 'content-type: application/json' \
  -d '{"query":"{ _meta { deployment } }"}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['_meta']['deployment'])")

# wait for allocations
TOTAL_EXPECTED=$((1 + N))
while true; do
  ALLOC_COUNT=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"query":"{ allocations(where: { status: Active }) { subgraphDeployment { ipfsHash } } }"}' \
    http://localhost:8000/subgraphs/name/graph-network \
    | ND="$NETWORK_DEPLOYMENT" python3 -c "import json,sys,os; d=os.environ['ND']; print(sum(1 for a in json.load(sys.stdin)['data']['allocations'] if a['subgraphDeployment']['ipfsHash']==d))")
  echo "$ALLOC_COUNT / $TOTAL_EXPECTED allocations"
  [ "$ALLOC_COUNT" -ge "$TOTAL_EXPECTED" ] && break
  sleep 5
done

# protect indexing-payments subgraph on the primary
cd /home/mainuser/local-network
python3 scripts/set-offchain-rule.py indexing-payments

# briefly pause primary so gateway routes to extras
docker pause indexer-service

# 200 queries through gateway — these go to extras while primary is paused.
# Trailing `|| true` is load-bearing: a curl --max-time timeout returns exit 28,
# which would abort the heredoc under set -e and leave the primary stuck paused.
SUCCESS=0
FAIL=0
for i in $(seq 1 200); do
  if curl -s --max-time 5 \
       "http://localhost:7700/api/deadbeefdeadbeefdeadbeefdeadbeef/deployments/id/$NETWORK_DEPLOYMENT" \
       -H 'content-type: application/json' \
       -d '{"query":"{ _meta { block { number } } }"}' >/dev/null 2>&1; then
    SUCCESS=$((SUCCESS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
done
echo "queries: $SUCCESS succeeded, $FAIL failed"

# unpause + resume + verify — runs unconditionally even if some queries failed
docker unpause indexer-service || true
python3 scripts/check-subgraph-sync.py --resume indexing-payments
python3 scripts/check-subgraph-sync.py
REMOTE
```

The `set-offchain-rule.py` script and `check-subgraph-sync.py` are part of the local-network repo and run from `/home/mainuser/local-network` on the VM.

Replace `N` in `TOTAL_EXPECTED=$((1 + N))` with the actual extras count before running the heredoc, since the heredoc is `'REMOTE'`-quoted (no local interpolation).

### 10. Trigger an IISA score refresh

The cronjob image runs scoring once and exits. After populating Redpanda with query history above, run a fresh scoring pass:

```bash
ssh lnet-test 'cd /home/mainuser/local-network && docker compose run --rm iisa-cronjob' 2>&1 | tail -10
```

Look at the last log line — `Scoring complete: mode=..., indexers=N, ...` — to confirm. Exit codes: `0` success, `1` scoring/push failure, `2` missing push token. The `indexers=N` count should equal `1 + extras`. If it's lower, the gateway hasn't routed to all indexers yet — send more queries (step 9) and retry.

### 11. Report

Summarize for the user:

- All running indexers with container names, addresses, and health (`ssh lnet-test 'docker ps --format "{{.Names}}\t{{.Status}}" | grep -E "indexer-(agent|service)"'`).
- Indexers visible in the network subgraph with URLs (output of step 7).
- IISA score count (last log line of step 10).

## Constraints

- Always use the explicit service-name list with `--no-deps --no-recreate` in step 5; never `--force-recreate` against a running stack — it bounces shared services and reverts contract state.
- The `compose/extra-indexers.yaml` path is added to `COMPOSE_FILE` in `.env` automatically by `gen-extra-indexers.py`. After the scp in step 3, no `-f compose/extra-indexers.yaml` flag is needed for subsequent `docker compose` calls; compose reads it from `.env` directly.
- Agents poll for on-chain staking automatically (up to 450s), so step 4 (`start-indexing-extra`) and step 5 (`up -d`) can be issued back-to-back; the agents wait for the on-chain state internally.
- Agents retry transient errors automatically (30 attempts, 10s delay). Don't manually restart unless the error is persistent and non-transient.
- Each extra service uses the **same Dockerfile context as the primary** (this branch's alignment with `gen-extra-indexers.py`'s rewrite). If you bump `${INDEXER_AGENT_VERSION}` or any other version pin in `.env`, the next `up -d` of extras picks up the new image automatically — no separate generator step needed.
- The pause/unpause trick in step 9 only routes traffic for queries issued during the pause window. Don't leave `indexer-service` paused — gateway will reject everything else with 5xx.
