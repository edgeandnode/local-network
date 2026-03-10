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

| Suffix | Mnemonic Index | Address |
|--------|---------------|---------|
| 2 | 2 | 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC |
| 3 | 3 | 0x90F79bf6EB2c4f870365E785982E1f101E93b906 |
| 4 | 4 | 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65 |
| 5 | 5 | 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc |

## Steps

### 1. Determine current extra indexer count

```bash
docker ps --format '{{.Names}}' | grep -oP 'indexer-agent-\K\d+' | sort -n | tail -1
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

First, run `start-indexing-extra` to register new indexers on-chain:

```bash
DOCKER_DEFAULT_PLATFORM= docker compose \
  -f docker-compose.yaml \
  -f compose/dev/dips.yaml \
  -f compose/extra-indexers.yaml \
  run --rm start-indexing-extra
```

Then start the actual containers with `--no-deps --no-recreate`. For each new suffix N:

```bash
DOCKER_DEFAULT_PLATFORM= docker compose \
  -f docker-compose.yaml \
  -f compose/dev/dips.yaml \
  -f compose/extra-indexers.yaml \
  up -d --no-deps --no-recreate postgres-N graph-node-N indexer-agent-N indexer-service-N tap-agent-N
```

`--no-deps` prevents compose from walking the dependency tree and bouncing shared services. `--no-recreate` prevents touching already-running containers.

### 5. Verify health

Indexer-services share a `flock`-serialized cargo build, so they come up sequentially. The first service to start builds the binary (~2-3 minutes if not cached); subsequent services acquire the lock, find the binary already built, and start immediately.

Wait 30 seconds after `up -d` completes, then check status:

```bash
docker ps --format '{{.Names}}\t{{.Status}}' | grep -E '(indexer-agent|indexer-service|tap-agent)-[0-9]' | sort
```

All agents and services should show `(healthy)`. If a service is still `(health: starting)`, it may be waiting for the cargo build lock -- wait another 60 seconds and recheck.

If an agent is stuck retrying (check `docker logs indexer-agent-N 2>&1 | tail -5`), the retry loop will show attempt counts. Common causes: `start-indexing-extra` hasn't completed yet (check `docker logs start-indexing-extra`), or a wrong address in JUNK_ACCOUNTS.

### 6. Report

Show a summary of all running indexers (primary + extras) with their container names, addresses, and health status.

## Constraints

- Always prefix docker compose with `DOCKER_DEFAULT_PLATFORM=`
- Always use all three compose files: `-f docker-compose.yaml -f compose/dev/dips.yaml -f compose/extra-indexers.yaml`
- Never use `--force-recreate` when adding indexers to a running stack
- The generator script is at `scripts/gen-extra-indexers.py`
- The `start-indexing-extra` container handles on-chain GRT staking and operator authorization
- Agents poll for on-chain staking automatically (up to 450s), so `start-indexing-extra` can run in parallel with container startup
- Agents retry automatically (30 attempts, 10s delay) -- don't manually restart unless the error is persistent and non-transient
- If COMPOSE_FILE in .environment doesn't include `compose/extra-indexers.yaml`, warn the user to add it
