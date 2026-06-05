---
name: index-published-subgraph
description: Make a Studio-published test subgraph queryable end-to-end on the local stack — mint curation signal, set an 'always' indexing rule so the indexer allocates, and restart the indexer-agent if its action queue is jammed on nonce drift. Use after publishing a subgraph from the Studio UI when you want an indexer to start indexing/allocating to it and to query its _logs (or any data) through the gateway. Trigger when the user asks to "get an indexer to index/allocate to" a published deployment, "signal + allocate" a subgraph, or make a freshly-published subgraph gateway-routable.
argument-hint: "<deployment-ipfs-hash> [agent-port] [signal-grt]"
---

# Index a Studio-Published Subgraph

Take a subgraph you've just published from the Studio UI (you have its `Qm…` deployment CID) and drive it to a state where a local indexer is allocated and indexing it, so `_logs` (and normal queries) route through the gateway.

It performs the three steps worked out manually:

1. **Curation signal** — the gateway only routes versions with `signalAmount > 0`. Mint signal on the deployment if it has none.
2. **`always` indexing rule** — the agent's global rule is `decisionBasis: rules` with `minSignal: null`, so it only allocates to deployments that carry an explicit rule. Without this the agent logs "No deployment changes are necessary" and never allocates.
3. **Restart-if-jammed (the conditional step)** — the agent gates *all* reconciliation behind its action queue ("There are N approved actions awaiting execution, will reconcile … once they are executed"). Routine `presentPOI` actions periodically wedge on `Transaction failed because nonce has already been used` (operator nonce drifts behind chain; BUG-022 family). When that happens, no allocation is ever created. The script detects this exact condition and restarts the indexer-agent, which resets its nonce manager and drains the queue. If the queue isn't jammed, it does **not** restart.

## Prerequisites

- The subgraph is **already published to GNS** via the Studio UI (this skill does not publish). If it isn't in the network subgraph yet, the script aborts with a clear message.
- The deployment was created with the **YAML-manifest** `deploy-studio-test-subgraphs.py`. If `manifest.network` is null (old JSON-manifest subgraph), the script still signals + allocates, but warns that the gateway will return "no valid versions" — those must be redeployed with a YAML manifest to be gateway-routable.
- Local Docker stack running; Foundry `cast` on PATH; run from the `local-network` repo root.

## Argument

`<deployment-ipfs-hash>` — required, the `Qm…` CID from Studio.
`[agent-port]` — optional, indexer-agent management port (default `7600` = primary indexer; extra indexers from `/add-indexers` use `17600 + n*10`).
`[signal-grt]` — optional, signal to mint if none exists (default `1000`).

## Run

```bash
scripts/index-published-subgraph.sh <deployment-ipfs-hash>
```

e.g. `scripts/index-published-subgraph.sh QmcXN6ECC6sUqrymygR7F1qGaNA3C7PyQbR9MbCtb1Nkc1`

The script is idempotent: re-running a deployment that's already signaled + allocated skips the mint, re-asserts the rule, finds the allocation immediately, and just prints the gateway query.

## What it prints at the end

- The GNS **subgraph id** to use in the gateway path (`/api/subgraphs/id/<subgraphId>` — note this is the *subgraph* id, not the `Qm…` deployment hash).
- A ready-to-run gateway `_logs` curl (Bearer `deadbeef…`, the only key the local gateway accepts).
- If `manifest.network` was null, a direct-graph-node curl instead (since the gateway can't route it).

## Notes

- **Signal source**: hardhat account 0 (the deployer, ~10B GRT). ~1% curation tax applies, so 1000 GRT minted shows as ~990 signal — expected.
- **Who allocates**: the rule is set on the agent at `[agent-port]`. For multi-indexer setups, run once per indexer port you want allocating, or just the primary.
- **The restart is the only durable unblock today.** The real fix is in the indexer-agent's nonce/transaction manager (operator nonce drifting behind chain). Until that lands, expect the queue to re-jam across sessions; this skill clears it each time.
- **Does not publish, curate from a specific wallet, or close allocations.** Signal is minted from account 0 for test purposes; the curation curator identity is irrelevant to indexer allocation decisions (only total deployment signal matters).
