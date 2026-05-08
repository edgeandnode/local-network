---
name: deploy-test-subgraphs
description: Publish test subgraphs to GNS on the local network. Use when the user asks to "deploy subgraphs", "add subgraphs", "deploy 50 subgraphs", "create test subgraphs", or wants to populate the network with subgraphs for testing. Also trigger when the user says a number followed by "subgraphs" (e.g. "deploy 500 subgraphs").
argument-hint: "[count] [prefix]"
---

# Deploy Test Subgraphs

Publish N subgraphs to GNS on the running local network. Each subgraph is built from a minimal block-tracker template (varying startBlock per subgraph), uploaded to IPFS, and published on-chain. **Not** deployed to graph-node, **not** curated, **not** allocated — they show up as "GNS-only" in `network-status.py` output.

## Targets

Both `scripts/deploy-test-subgraph.py` and `scripts/network-status.py` reach `localhost:5001` (IPFS), `localhost:8545` (chain RPC), `localhost:8000` and `localhost:8030` (graph-node). On a Mac+VM setup these endpoints only resolve correctly **on the VM**, so run via SSH. Both scripts also shell out to `cast` (Foundry) and `npx graph` (Graph CLI), so the VM needs Foundry and Node.js >= 20.18.1 installed once. Locally on Mac with the stack on Mac, drop the `ssh lnet-test` wrapper and run the same commands directly.

VM path: `/home/mainuser/local-network`.

## VM prerequisites (one-time)

If the VM doesn't have Foundry yet, install it from the release tarball (the `foundryup` installer refuses while the chain container's anvil is "running"):

```bash
ssh lnet-test 'mkdir -p ~/.foundry/bin
TAG=$(curl -s https://api.github.com/repos/foundry-rs/foundry/releases/latest | grep "\"tag_name\":" | cut -d"\"" -f4)
curl -sL "https://github.com/foundry-rs/foundry/releases/download/${TAG}/foundry_${TAG}_linux_amd64.tar.gz" \
  | tar -xz -C ~/.foundry/bin
sudo ln -sf $HOME/.foundry/bin/cast   /usr/local/bin/cast
sudo ln -sf $HOME/.foundry/bin/forge  /usr/local/bin/forge
sudo ln -sf $HOME/.foundry/bin/anvil  /usr/local/bin/anvil
sudo ln -sf $HOME/.foundry/bin/chisel /usr/local/bin/chisel'
```

If Node.js is missing or older than 20.18.1 (Ubuntu 24.04's apt nodejs is 18.x — too old for Graph CLI), install Node 22 via NodeSource:

```bash
ssh lnet-test 'curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs'
```

Verify both: `ssh lnet-test 'cast --version && node --version && npm --version'`.

## Steps

```bash
ssh lnet-test 'cd /home/mainuser/local-network && python3 scripts/deploy-test-subgraph.py <count> [prefix]'
```

- `count` defaults to 1 if the user doesn't specify a number.
- `prefix` defaults to `test-subgraph` — each subgraph is named `<prefix>-1`, `<prefix>-2`, etc.

The script builds the subgraph manifest once (~10s, runs `npm install` + `npx graph codegen` + `npx graph build` in a tempdir), then each on-chain publish is sub-second. 100 subgraphs takes ~30s total.

After publishing, run network-status and put the result in a code block so the user sees the updated state:

```bash
ssh lnet-test 'cd /home/mainuser/local-network && python3 scripts/network-status.py'
```

Newly-published subgraphs appear under `GNS-only (N published on-chain, not indexed)`; existing indexed ones stay in their normal sections.
