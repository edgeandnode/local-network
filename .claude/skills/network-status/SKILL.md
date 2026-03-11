---
name: network-status
description: Show the current state of the local Graph protocol network. Use when the user asks for "network status", "show me the network", "what's deployed", "which indexers", "which subgraphs", "what's running", or wants to see allocations, sync status, or the network tree.
---

Run `python3 scripts/network-status.py` from the local-network repo root to fetch the current network state.

Output the FULL result directly as text in a code block so it renders inline without the user needing to expand tool results. Do NOT truncate, summarize, or abbreviate any part of the output -- show every line including all deployment hashes.
