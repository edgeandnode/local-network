---
name: fresh-deploy
description: Full stack reset and fresh deploy of the local-network Docker Compose environment. Use when the user asks to tear down and redeploy, do a fresh deploy, reset the stack, or bring everything up from scratch. Also use after merging PRs that change container code, or when debugging stuck state.
---

# Fresh Deploy

Reset the local-network Docker Compose environment to a clean state and bring all services up ready for DIPs testing.

## Prerequisites

The contracts repo at `$CONTRACTS_SOURCE_ROOT` (typically `/Users/samuel/Documents/github/contracts`) must be on `indexing-payments-management-audit` (PR #1301) with three local commits applied on top:

1. Cherry-pick `02b6996e` from `escrow-management` -- adds RecurringCollector Ignition module, wires it into SubgraphService deployment, and links external libraries
2. Cherry-pick `d2a0d30e` from `escrow-management` -- adds `RecurringCollector` to `GraphHorizonContractNameList` in toolshed so it gets written to horizon.json
3. Local fix for BUG-007 -- adds `{ after: [GraphPeripheryModule, HorizonProxiesModule] }` to the `deployImplementation` call in `packages/horizon/ignition/modules/core/HorizonStaking.ts`

After applying these, the toolshed package must be compiled: `cd packages/toolshed && pnpm build:self`.

To verify the local commits are present, check: `cd $CONTRACTS_SOURCE_ROOT && git log --oneline -5`. The top 3 commits should be the fix and two cherry-picks.

## Steps

### 1. Tear down everything including volumes

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml down -v
```

This destroys all data: chain state, postgres, subgraph deployments, config volume with contract addresses.

### 2. Clear stale Ignition journals

If a previous deployment failed (especially `graph-contracts`), the Hardhat Ignition journal at `$CONTRACTS_SOURCE_ROOT/packages/subgraph-service/ignition/deployments/chain-1337/` will contain partial state that prevents a clean redeploy. Delete it:

```bash
rm -rf $CONTRACTS_SOURCE_ROOT/packages/subgraph-service/ignition/deployments/chain-1337
```

This is safe after a `down -v` since the chain state it references no longer exists.

### 3. Bring everything up

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml up -d --build
```

The `--build` flag ensures any changes to `run.sh` scripts or Dockerfiles are picked up (e.g. chain's `--block-time` flag, config changes baked into images). Without it, Docker reuses cached images and local changes are silently ignored.

Wait for containers to stabilize. The `graph-contracts` container runs first (deploys all Solidity contracts and writes addresses to the config volume), then `subgraph-deploy` deploys three subgraphs (network, TAP, block-oracle). Other services start as their health check dependencies are met.

**Note:** The initial `up -d` may exit with an error if `start-indexing` fails. This is expected -- see step 5. If `graph-contracts` itself fails, check its logs -- the most likely cause is a missing prerequisite commit (see Prerequisites) or a stale Ignition journal (see step 2).

### 4. Verify RecurringCollector was written to horizon.json

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml exec indexer-agent \
  jq '.["1337"].RecurringCollector' /opt/config/horizon.json
```

If this returns null, the contracts toolshed wasn't rebuilt after cherry-picking the whitelist fix. Run `cd $CONTRACTS_SOURCE_ROOT/packages/toolshed && pnpm build:self` and repeat from step 1.

### 5. Fix nonce race failures

Multiple containers use ACCOUNT0 concurrently after `graph-contracts` finishes (`start-indexing`, `tap-escrow-manager`). This causes "nonce too low" errors that can fail either container. The cascade is the real problem: if `start-indexing` fails, `dipper` and `ready` never start because they depend on it.

Check whether `start-indexing` exited successfully:

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml ps -a start-indexing --format '{{.Status}}'
```

If it shows `Exited (1)`, restart it:

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml start start-indexing
```

Always restart `tap-escrow-manager` regardless of whether `start-indexing` succeeded. Even when authorization succeeds, the deposit step can hit "nonce too low" from competing with `start-indexing`. The `AlreadyAuthorized` error on restart is harmless -- it re-runs the deposit with a fresh nonce.

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml restart tap-escrow-manager
```

### 6. Bring up any cascade-failed containers

If `start-indexing` failed on the initial `up -d`, containers that depend on it (`dipper`, `ready`) will be stuck in `Created` state. Run `up -d` again to catch them:

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml up -d --build
```

This is idempotent -- already-running containers are left alone.

### 7. Verify signer authorization

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml logs tap-escrow-manager --since 60s 2>&1 | grep -i "authorized"
```

Expected: either `authorized signer=0x70997970C51812dc3A010C7d01b50e0d17dc79C8` (fresh auth) or `AuthorizableSignerAlreadyAuthorized` (already done on first run). Both are fine.

### 8. Wait for TAP subgraph indexing, then verify dipper

The TAP subgraph needs to index the `SignerAuthorized` event before the indexer-service will accept paid queries. Dipper may restart once or twice with "bad indexers: BadResponse(402)" during this window -- this is normal and self-resolves.

Check:

```bash
DOCKER_DEFAULT_PLATFORM= docker compose -f docker-compose.yaml -f compose/dev/dips.yaml ps dipper --format '{{.Name}} {{.Status}}'
```

Should show `dipper Up ... (healthy)`. If still restarting after 60 seconds, check gateway logs for persistent 402s.

### 9. Full status check

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

- **ACCOUNT0 nonce race**: `start-indexing` and `tap-escrow-manager` both use ACCOUNT0 concurrently after `graph-contracts` finishes. Either can fail with "nonce too low". If `start-indexing` fails, `dipper` and `ready` never start (cascade). The fix is to restart the failed container and run `up -d` again.
- **Stale Ignition journals**: After a failed `graph-contracts` deployment, the journal at `packages/subgraph-service/ignition/deployments/chain-1337/` contains partial state. A fresh `down -v` destroys the chain but not the journal (it's in the mounted source). Always delete it before retrying (step 2).
- The contracts toolshed must be compiled (JS, not just TS) for the RecurringCollector whitelist to take effect. Use `pnpm build:self` in `packages/toolshed` (not `pnpm build` which fails on the `interfaces` package).

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
