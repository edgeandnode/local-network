---
name: network-status
description: Show the current state of the local Graph protocol network. Use when the user asks for "network status", "show me the network", "what's deployed", "which indexers", "which subgraphs", "what's running", or wants to see allocations, sync status, or the network tree.
---

The script hits `localhost:8030` (graph-node status), `localhost:8000` (graph-node GraphQL), `localhost:8545` (chain RPC) and runs `docker exec postgres psql ... dipper_1` for the dipper postgres lookup. It prints a network > subgraph > indexer tree (with allocated stake and sync health), then idle indexers (registered on-chain, no active allocations), unallocated and GNS-only subgraphs (the latter flagged `dips` when dipper has an indexing request for them), and a contract-health check that the RewardsManager points at the SubgraphService rewards issuer.

On a Mac+VM setup all of those only resolve correctly on the VM, so run via SSH:

```bash
ssh lnet-test 'cd /home/mainuser/local-network && python3 scripts/network-status.py'
```

For a local-only docker setup, drop the `ssh lnet-test` wrapper and use the Mac path.

Output the FULL result directly as text in a code block so it renders inline without the user needing to expand tool results. Do NOT truncate, summarize, or abbreviate any part of the output — show every line including all deployment hashes.
