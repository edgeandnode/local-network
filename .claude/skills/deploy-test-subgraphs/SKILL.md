---
name: deploy-test-subgraphs
description: Publish test subgraphs to GNS on the local network. Use when the user asks to "deploy subgraphs", "add subgraphs", "deploy 50 subgraphs", "create test subgraphs", or wants to populate the network with subgraphs for testing. Also trigger when the user says a number followed by "subgraphs" (e.g. "deploy 500 subgraphs").
argument-hint: "[count] [prefix]"
---

Run `python3 scripts/deploy-test-subgraph.py <count> [prefix]` from the local-network repo root.

- `count` defaults to 1 if the user doesn't specify a number
- `prefix` defaults to `test-subgraph` -- each subgraph is named `<prefix>-1`, `<prefix>-2`, etc.
- Subgraphs are published to GNS on-chain only -- they are NOT deployed to graph-node and will not be indexed

The script builds once (~10s), then each publish is sub-second. 100 subgraphs takes ~30s total.

After publishing, run `python3 scripts/network-status.py` and output the result in a code block so the user can see the updated network state.
