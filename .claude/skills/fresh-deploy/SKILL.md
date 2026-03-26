---
name: fresh-deploy
description: Full stack reset and fresh deploy of the local-network Docker Compose environment. Use when the user asks to tear down and redeploy, do a fresh deploy, reset the stack, or bring everything up from scratch. Also use after merging PRs that change container code, or when debugging stuck state.
---

# Fresh Deploy

Reset the local-network Docker Compose environment to a clean state and bring all services up ready for DIPs testing.

## Prerequisites

The contracts repo at `$CONTRACTS_SOURCE_ROOT` (typically `/Users/samuel/Documents/github/contracts`) must be on `fix/horizon-staking-ignition-dependency` (or `mde/dips-ignition-deployment` + BUG-007 fix). This branch has `IndexingAgreementManager`, RecurringCollector in toolshed/ignition natively, and the HorizonStaking deployment ordering fix.

After checking out the branch, the toolshed package must be compiled: `cd packages/toolshed && pnpm build:self`.

To verify: `cd $CONTRACTS_SOURCE_ROOT && git log --oneline -3` should show the HorizonStaking fix on top of the mde branch.

## Steps

### 1. Tear down everything including volumes

Build the compose file list dynamically to include extra-indexers if present. This is critical -- omitting `compose/extra-indexers.yaml` leaves extra indexer containers and their postgres volumes alive, causing stale state on the next deploy (agents think they're registered on the old chain).

```bash
COMPOSE_FILES="-f docker-compose.yaml -f compose/dev/dips.yaml"
[ -f compose/extra-indexers.yaml ] && COMPOSE_FILES="$COMPOSE_FILES -f compose/extra-indexers.yaml"
DOCKER_DEFAULT_PLATFORM= docker compose $COMPOSE_FILES down -v
```

This destroys all data: chain state, postgres (including extra indexer postgres volumes), subgraph deployments, config volume with contract addresses.

### 2. Clear stale Ignition journals

If a previous deployment failed (especially `graph-contracts`), the Hardhat Ignition journal at `$CONTRACTS_SOURCE_ROOT/packages/subgraph-service/ignition/deployments/chain-1337/` will contain partial state that prevents a clean redeploy. Delete it:

```bash
rm -rf $CONTRACTS_SOURCE_ROOT/packages/subgraph-service/ignition/deployments/chain-1337
```

This is safe after a `down -v` since the chain state it references no longer exists.

### 3. Bring everything up

Use only the base compose files for the initial deploy. Extra indexers are added separately via the `/add-indexers` skill after the core stack is healthy.

Use `--no-build` by default — run.sh scripts are volume-mounted, so changes are picked up without rebuilding images. Only use `--build` when Dockerfiles, build args, or base images have changed.

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml up -d --no-build
```

If images don't exist yet (first deploy ever) or Dockerfiles changed, use `--build` instead:

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml up -d --build
```

All services start in parallel with minimal dependencies (chain + postgres only for dev containers). Services wait internally for their runtime dependencies (network subgraph, gateway, iisa) rather than blocking at the compose level. A single `up -d` is sufficient — no need to run it multiple times.

Wait for containers to stabilize. The `graph-contracts` container runs first (deploys all Solidity contracts and writes addresses to the config volume), then `subgraph-deploy` deploys three subgraphs (network, TAP, block-oracle). Other services start as their health check dependencies are met.

### 4. Verify RecurringCollector was written to horizon.json

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml exec indexer-agent \
  jq '.["1337"].RecurringCollector' /opt/config/horizon.json
```

If this returns null, the contracts toolshed wasn't rebuilt. Run `cd $CONTRACTS_SOURCE_ROOT/packages/toolshed && pnpm build:self` and repeat from step 1.

### 5. Verify signer authorization

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml logs tap-escrow-manager --since 60s 2>&1 | grep -i "authorized"
```

Expected: either `authorized signer=0x70997970C51812dc3A010C7d01b50e0d17dc79C8` (fresh auth) or `AuthorizableSignerAlreadyAuthorized` (already done on first run). Both are fine.

### 6. Wait for TAP subgraph indexing, then verify dipper

The TAP subgraph needs to index the `SignerAuthorized` event before the indexer-service will accept paid queries. Dipper may restart once or twice with "bad indexers: BadResponse(402)" during this window -- this is normal and self-resolves.

Check:

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml ps dipper --format '{{.Name}} {{.Status}}'
```

Should show `dipper Up ... (healthy)`. If still restarting after 60 seconds, check gateway logs for persistent 402s.

### 6b. Verify indexing-payments subgraph

The indexing-payments subgraph is critical for DIPs -- dipper's chain_listener reads it to detect on-chain `IndexingAgreementAccepted` events. Without it, agreements expire after 300 seconds regardless of whether indexer-agents accepted them on-chain (BUG-012, BUG-014).

Check it's deployed and syncing:

```bash
python3 scripts/check-subgraph-sync.py indexing-payments
```

If exit code is 1, the subgraph-deploy container may still be running. Check `DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml logs subgraph-deploy 2>&1 | tail -20`.

Verify the primary agent has the offchain rule (set by `run-dips.sh`'s wait loop):

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml \
  logs indexer-agent 2>&1 | grep -m1 "Adding indexing-payments"
```

Expected: a log line showing the indexing-payments deployment was added to offchain subgraphs. If instead you see `"WARNING: indexing-payments subgraph not found after 3m"`, the agent started before subgraph-deploy finished. Set the offchain rule manually:

```bash
python3 scripts/set-offchain-rule.py indexing-payments
```

### 7. Full status check

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml ps --format '{{.Name}} {{.Status}}' | sort
```

All services should be Up. The key health-checked services are: chain, graph-node, postgres, ipfs, redpanda, indexer-agent, indexer-service, gateway, iisa-scoring, iisa, block-oracle, dipper.

## Architecture notes

The authorization chain that makes gateway queries work:

1. `graph-contracts` deploys all contracts, writes addresses to config volume (`horizon.json`, `tap-contracts.json`)
2. `subgraph-deploy` deploys the TAP subgraph pointing at the Horizon PaymentsEscrow address (from `horizon.json`)
3. `tap-escrow-manager` authorizes ACCOUNT1 (gateway signer) on the PaymentsEscrow contract
4. The TAP subgraph indexes the `SignerAuthorized` event
5. `indexer-service` queries the TAP subgraph, sees ACCOUNT1 is authorized for ACCOUNT0 (the payer)
6. Gateway queries signed by ACCOUNT1 are accepted with 200 instead of 402

## Known issues

- **Stale Ignition journals**: After a failed `graph-contracts` deployment, the journal at `packages/subgraph-service/ignition/deployments/chain-1337/` contains partial state. A fresh `down -v` destroys the chain but not the journal (it's in the mounted source). Always delete it before retrying (step 2).
- The contracts toolshed must be compiled (JS, not just TS) for the RecurringCollector whitelist to take effect. Use `pnpm build:self` in `packages/toolshed` (not `pnpm build` which fails on the `interfaces` package).
- **Extra indexer stale state**: If `compose/extra-indexers.yaml` is not included in the `down -v` command, extra indexer containers and their postgres volumes survive the teardown. On the next deploy, agents have stale state from the old chain -- they believe they're already registered and never re-register URLs on the new chain. The network subgraph then shows `url: null` for these indexers and IISA can't select them.
- **Use `--no-build` for speed**: Run.sh scripts are volume-mounted, so changes are picked up without image rebuilds. Only use `--build` when Dockerfiles or build args have changed. Using `--no-build` saves ~10 minutes on cached deploys.

## Key contract addresses (change each deploy)

Read from the config volume:

```bash
# All Horizon contracts
docker compose exec indexer-agent cat /opt/config/horizon.json | jq '.["1337"]'

# TAP contracts
docker compose exec indexer-agent cat /opt/config/tap-contracts.json

# Important ones for manual testing:
# GRT Token: jq '.["1337"].L2GraphToken.address' horizon.json
# PaymentsEscrow: jq '.["1337"].PaymentsEscrow.address' horizon.json
# RecurringCollector: jq '.["1337"].RecurringCollector.address' horizon.json
# GraphTallyCollector: jq '.["1337"].GraphTallyCollector.address' horizon.json
```

## Accounts

- ACCOUNT0 (`0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`): deployer, admin, payer
- ACCOUNT1 (`0x70997970C51812dc3A010C7d01b50e0d17dc79C8`): gateway signer
- RECEIVER (`0xf4EF6650E48d099a4972ea5B414daB86e1998Bd3`): indexer (mnemonic index 0 of "test...zero")
