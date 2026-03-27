---
name: add-indexers
description: "Add extra indexers to the local Graph protocol network. Use when the user asks to add indexers, spin up another indexer, get more indexers up, bring up new indexers, or wants extra indexers for testing. Also trigger when user says a number followed by 'indexers' (e.g. 'add 3 indexers', 'spin up 2 more')."
argument-hint: "[count]"
allowed-tools:
  - Bash
  - Read
  - Grep
---

# Add Extra Indexers

Add N extra indexers to the running local network. Each extra indexer gets a fully isolated stack: postgres, graph-node, indexer-agent, indexer-service, and tap-agent. Protocol subgraphs (network, epoch, TAP) are read from the primary graph-node -- extra graph-nodes only handle actual indexing work.

The argument is the number of NEW indexers to add (defaults to 1).

## Working directory

All commands must run from the local-network project root. Always cd first:

```bash
cd /Users/samuel/Documents/github/local-network
```

## Accounts

Extra indexers use hardhat "junk" mnemonic accounts starting at index 2. Maximum 18 extra (indices 2-19).

Each indexer gets a unique operator derived from a mnemonic of the form `test test test ... test {bip39_word}` (11 "test" + 1 valid checksum word). The generator handles mnemonic validation, operator address derivation, ETH funding, on-chain `setOperator` authorization for both SubgraphService and HorizonStaking, and PaymentsEscrow deposits for DIPs signer validation.

| Suffix | Mnemonic Index | Address |
|--------|---------------|---------|
| 2 | 2 | 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC |
| 3 | 3 | 0x90F79bf6EB2c4f870365E785982E1f101E93b906 |
| 4 | 4 | 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65 |
| 5 | 5 | 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc |

## Steps

### 1. Determine current extra indexer count

```bash
docker ps --format '{{.Names}}' | grep 'indexer-agent-' | sed 's/indexer-agent-//' | sort -n | tail -1
```

If no matches, current extra count is 0. Otherwise the highest suffix minus 1 gives the count (suffix 2 = 1 extra, suffix 3 = 2 extras, etc.).

### 2. Calculate new total

New total = current extra count + number requested by user.

Cap at 18. If the user asks for more than available slots, warn and cap.

### 3. Regenerate compose file

```bash
python3 scripts/gen-extra-indexers.py <NEW_TOTAL>
```

This regenerates the full compose file for ALL extras (existing + new). It's idempotent -- running it with the same number produces the same file.

### 4. Bring up new containers

Two-step process to avoid bouncing shared services.

First, run `start-indexing-extra` to register new indexers on-chain (stake, operator auth, escrow deposits):

```bash
DOCKER_DEFAULT_PLATFORM= docker compose \
  -f docker-compose.yaml \
  -f compose/dev/dips.yaml \
  -f compose/extra-indexers.yaml \
  run --rm start-indexing-extra
```

Then start all new containers in a single command with `--no-deps --no-recreate`. List all new service names space-separated:

```bash
DOCKER_DEFAULT_PLATFORM= docker compose \
  -f docker-compose.yaml \
  -f compose/dev/dips.yaml \
  -f compose/extra-indexers.yaml \
  up -d --no-deps --no-recreate postgres-2 graph-node-2 indexer-agent-2 indexer-service-2 tap-agent-2 [... all suffixes ...]
```

`--no-deps` prevents compose from walking the dependency tree and bouncing shared services. `--no-recreate` prevents touching already-running containers.

### 5. Verify container health

Indexer-services share a `flock`-serialized cargo build, so they come up sequentially. The first service to start builds the binary (~2-3 minutes if not cached); subsequent services acquire the lock, find the binary already built, and start immediately.

Poll every 5 seconds until all agents and services are healthy (do NOT use a fixed sleep):

```bash
EXPECTED=N  # number of extras
while true; do
  HEALTHY=$(docker ps --format '{{.Names}} {{.Status}}' | grep -E '(indexer-agent|indexer-service)-[0-9]' | grep -c healthy || true)
  echo "$HEALTHY / $((EXPECTED * 2)) healthy"
  [ "$HEALTHY" -ge "$((EXPECTED * 2))" ] && break
  sleep 5
done
```

### 6. Wait for network subgraph to index URL registrations

After agents start, they call `subgraphService.register(url, geo)` on-chain. The network subgraph must index these events before IISA or dipper can see the new indexers. Poll every 5 seconds until all indexers have URLs (do NOT use a fixed sleep):

```bash
TOTAL_EXPECTED=$((1 + N))  # primary + extras
while true; do
  COUNT=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"query":"{ indexers(where: { url_not: \"\" }) { id } }"}' \
    http://localhost:8000/subgraphs/name/graph-network \
    | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']['indexers']))")
  echo "$COUNT / $TOTAL_EXPECTED indexers with URLs"
  [ "$COUNT" -ge "$TOTAL_EXPECTED" ] && break
  sleep 5
done
```

### 7. Set indexing rules on extra agents

Extra agents start with only the global rule and no subgraph-specific allocations. Without allocations, the gateway won't route queries to them, so they'll never build query history in Redpanda, and the IISA cronjob will exclude them from scoring (chicken-and-egg).

Set an `always` rule for the network subgraph on each extra agent so they allocate and start serving queries:

```bash
for port in 17620 17630 17640 17650; do
  curl -s http://localhost:$port/ -H 'content-type: application/json' -d '{
    "query": "mutation setIndexingRule($rule: IndexingRuleInput!) { setIndexingRule(identifier: \"QmPdbQaRCMhgouSZSW3sHZxU3M8KwcngWASvreAexzmmrh\", rule: $rule) { identifier decisionBasis } }",
    "variables": {
      "rule": {
        "identifier": "QmPdbQaRCMhgouSZSW3sHZxU3M8KwcngWASvreAexzmmrh",
        "identifierType": "deployment",
        "allocationAmount": "1000000000000000000",
        "decisionBasis": "always",
        "protocolNetwork": "eip155:1337"
      }
    }
  }'
done
```

The port mapping is `17600 + (suffix * 10)` — suffix 2 = 17620, suffix 3 = 17630, etc. Only hit ports for the actual extras that exist. The network subgraph deployment ID (`QmPdbQaR...`) is stable across deploys since it's derived from the schema + mappings, but verify with `curl -s http://localhost:8000/subgraphs/name/graph-network -H 'content-type: application/json' -d '{"query":"{ _meta { deployment } }"}' | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['_meta']['deployment'])"` if unsure.

After setting rules, agents will allocate within their next reconciliation cycle (~15s with the local dev polling interval). The gateway will then route queries to all indexers, building Redpanda history for IISA scoring.

### 8. Poll for allocations, then send gateway queries

Poll the network subgraph for allocations every 5 seconds until extras have allocated (do NOT use a fixed sleep).

**Important:** The `subgraphDeployment` field is a relationship, not a string. Use `subgraphDeployment_: { ipfsHash: "..." }` for filtering, not `subgraphDeployment: "..."`.

```bash
NETWORK_DEPLOYMENT=$(curl -s http://localhost:8000/subgraphs/name/graph-network \
  -H 'content-type: application/json' \
  -d '{"query":"{ _meta { deployment } }"}' | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['_meta']['deployment'])")

TOTAL_EXPECTED=$((1 + N))  # primary + extras
while true; do
  ALLOC_COUNT=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"query":"{ allocations(where: { status: Active }) { subgraphDeployment { ipfsHash } } }"}' \
    http://localhost:8000/subgraphs/name/graph-network \
    | python3 -c "import json,sys; print(sum(1 for a in json.load(sys.stdin)['data']['allocations'] if a['subgraphDeployment']['ipfsHash'] == '${NETWORK_DEPLOYMENT}'))")
  echo "$ALLOC_COUNT / $TOTAL_EXPECTED allocations"
  [ "$ALLOC_COUNT" -ge "$TOTAL_EXPECTED" ] && break
  sleep 5
done
```

Once allocations exist, build Redpanda history for ALL indexers. The gateway's candidate-selection algorithm heavily favors the primary indexer (highest stake), so extras never get queries naturally. Temporarily pause the primary to force the gateway to route to extras.

Before pausing, protect the indexing-payments subgraph by setting an offchain indexing rule on the primary agent. Without this, the agent detects the paused service as unhealthy and pauses all subgraphs without allocations -- including indexing-payments. The reconciliation loop then re-pauses it even after `subgraph_resume` because there is no offchain rule to override the automatic behavior (BUG-014).

```bash
# Protect indexing-payments subgraph before pausing the primary service
python3 scripts/set-offchain-rule.py indexing-payments

# Pause primary so gateway routes to extras
docker pause indexer-service

# Send queries -- these will be served by extra indexers
for i in $(seq 1 200); do
  curl -s --max-time 5 "http://localhost:7700/api/deadbeefdeadbeefdeadbeefdeadbeef/deployments/id/${NETWORK_DEPLOYMENT}" \
    -H 'content-type: application/json' \
    -d '{"query":"{ _meta { block { number } } }"}' > /dev/null 2>&1
done

# Unpause primary
docker unpause indexer-service

# Resume any paused subgraphs and verify sync
# The offchain rule set above prevents the agent from re-pausing indexing-payments.
python3 scripts/check-subgraph-sync.py --resume indexing-payments
python3 scripts/check-subgraph-sync.py
```

### 9. Trigger IISA score refresh

The IISA cronjob exposes `POST /run` on port 9090 for manual scoring runs. Trigger it and poll the logs for completion (do NOT use a fixed sleep):

```bash
DOCKER_DEFAULT_PLATFORM= docker compose \
  -f docker-compose.yaml \
  -f compose/dev/dips.yaml \
  -f compose/extra-indexers.yaml \
  exec iisa-cronjob curl -s -X POST http://localhost:9090/run
```

Poll for scoring completion:

```bash
while true; do
  RESULT=$(DOCKER_DEFAULT_PLATFORM= docker compose \
    -f docker-compose.yaml -f compose/dev/dips.yaml -f compose/extra-indexers.yaml \
    logs iisa-cronjob --since 10s 2>&1 | grep "Scoring complete" | tail -1)
  if [ -n "$RESULT" ]; then
    echo "$RESULT"
    break
  fi
  sleep 5
done
```

### 10. Report

Show a summary including:
- All running indexers (primary + extras) with container names, addresses, and health status
- Number of indexers visible in the network subgraph (with URLs)
- Number of indexers scored by IISA
- Confirmation that the pipeline is ready for `/send-indexing-request`

## Constraints

- Always prefix docker compose with `DOCKER_DEFAULT_PLATFORM=`
- Always use all three compose files: `-f docker-compose.yaml -f compose/dev/dips.yaml -f compose/extra-indexers.yaml`
- Never use `--force-recreate` when adding indexers to a running stack
- The generator script is at `scripts/gen-extra-indexers.py`
- The `start-indexing-extra` container handles on-chain GRT staking, operator authorization, and PaymentsEscrow deposits
- Agents poll for on-chain staking automatically (up to 450s), so `start-indexing-extra` can run in parallel with container startup
- Agents retry automatically (30 attempts, 10s delay) -- don't manually restart unless the error is persistent and non-transient
- If COMPOSE_FILE in .environment doesn't include `compose/extra-indexers.yaml`, warn the user to add it
- The `/fresh-deploy` skill must include `compose/extra-indexers.yaml` in its `down -v` command, otherwise extra indexer postgres volumes survive and agents have stale state on the next deploy
