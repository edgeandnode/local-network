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

Wait 30 seconds after `up -d` completes, then check status:

```bash
docker ps --format '{{.Names}}\t{{.Status}}' | grep -E '(indexer-agent|indexer-service)-[0-9]' | sort
```

All agents and services should show `(healthy)`. If a service is still `(health: starting)`, it may be waiting for the cargo build lock -- wait another 60 seconds and recheck.

### 6. Wait for network subgraph to index URL registrations

After agents start, they call `subgraphService.register(url, geo)` on-chain. The network subgraph must index these events before IISA or dipper can see the new indexers. Poll until all indexers have URLs:

```bash
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"query":"{ indexers(where: { url_not: \"\" }) { id } }"}' \
  http://localhost:8000/subgraphs/name/graph-network \
  | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']['indexers']))"
```

This should return `TOTAL_EXPECTED` (1 primary + N extras). If it's lower, the subgraph is still catching up -- wait 10 seconds and recheck. Typically takes 30-90 seconds after agents register.

### 7. Trigger IISA score refresh

The IISA cronjob exposes `POST /run` on port 9090 for manual scoring runs. Without triggering it, IISA won't see the new indexers until the next scheduled cycle (default 120s).

```bash
DOCKER_DEFAULT_PLATFORM= docker compose \
  -f docker-compose.yaml \
  -f compose/dev/dips.yaml \
  -f compose/extra-indexers.yaml \
  exec iisa-cronjob curl -s -X POST http://localhost:9090/run
```

Then verify scores were written for the expected number of indexers:

```bash
DOCKER_DEFAULT_PLATFORM= docker compose \
  -f docker-compose.yaml \
  -f compose/dev/dips.yaml \
  -f compose/extra-indexers.yaml \
  logs iisa-cronjob --since 30s 2>&1 | grep -E "Wrote|indexers"
```

### 8. Report

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
