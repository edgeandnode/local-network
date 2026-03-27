---
name: network-status
description: Show the current state of the local Graph protocol network. Use when the user asks for "network status", "show me the network", "what's deployed", "which indexers", "which subgraphs", "what's running", or wants to see allocations, sync status, or the network tree.
---

Run from the local-network project root (`cd /Users/samuel/Documents/github/local-network` first):

```bash
cd /Users/samuel/Documents/github/local-network
python3 scripts/network-status.py
```

Output the FULL result directly as text in a code block so it renders inline without the user needing to expand tool results. Do NOT truncate, summarize, or abbreviate any part of the output -- show every line including all deployment hashes.
