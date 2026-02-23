# Task: Graph Explorer Integration

> Created: 2026-02-20

## Problem

Several BaselineTestPlan cycles (1-2) reference Explorer UI operations for staking, delegation, and curation. Currently these are done by `graph-contracts` during deployment or by `cast send` in scripts. There is no way to:

1. Visually verify protocol state during development/testing
2. Test the actual UI flows that indexers use in production
3. Reference exact UI components when documenting test equivalents

## Objective

Add Graph Explorer as an optional service in the local network, providing both a visual development tool and a reference for what contract calls the UI makes.

## Source

The Graph Explorer repository is available locally at `/git/edgeandnode/graph-explorer/graph-explorer`.

### Architecture

- **Next.js 14** frontend, no backend database
- All data from network subgraph GraphQL + direct contract calls via Wagmi/Viem
- Docker support: multi-stage build, port 3000
- All required infrastructure already exists in local-network (graph-node, subgraphs, chain RPC, IPFS)

### Key Finding: No API Layer

Explorer has **no REST/GraphQL API for write operations**. All staking, delegation, and curation operations are direct smart contract calls from the browser via Wagmi hooks. This means:

- For test automation, `cast send` is the equivalent of what the UI does
- The value of Explorer in local-network is **visual verification and reference**, not scripting
- Test scripts should reference the Explorer component that makes each call

## Contract Call Reference

This maps Explorer UI actions to the contract calls test scripts should make:

### Curation

| UI Action          | Explorer Component         | Contract   | Function                                |
| ------------------ | -------------------------- | ---------- | --------------------------------------- |
| Signal (version)   | `SignalForm.tsx:238-257`   | L2Curation | `mint(bytes32, uint256, uint256)`       |
| Signal (named)     | `SignalForm.tsx:238-257`   | L2GNS      | `mintSignal(uint256, uint256, uint256)` |
| Unsignal (version) | `UnsignalForm.tsx:202-224` | L2Curation | `burn(bytes32, uint256, uint256)`       |
| Unsignal (named)   | `UnsignalForm.tsx:202-224` | L2GNS      | `burnSignal(uint256, uint256, uint256)` |

### Delegation

| UI Action  | Explorer Component                     | Contract       | Function                                       |
| ---------- | -------------------------------------- | -------------- | ---------------------------------------------- |
| Delegate   | `DelegateTransactionContext.tsx:40-62` | HorizonStaking | `delegate(address, address, uint256, uint256)` |
| Undelegate | `UndelegateFormDefinition.tsx:62-87`   | HorizonStaking | `undelegate(address, address, uint256)`        |

### Staking

| UI Action | Explorer Component        | Contract       | Function                                                          |
| --------- | ------------------------- | -------------- | ----------------------------------------------------------------- |
| Stake     | `StakeForm.tsx:104-120`   | HorizonStaking | `stake(uint256)` or `stakeToProvision(address, address, uint256)` |
| Unstake   | `UnstakeForm.tsx:101-146` | HorizonStaking | `unstake(uint256)` or `thaw(address, address, uint256)`           |

### Token Approval (all operations)

| UI Action     | Explorer Component           | Contract     | Function                    |
| ------------- | ---------------------------- | ------------ | --------------------------- |
| Approve spend | `GraphTokenApprovalFlow.tsx` | L2GraphToken | `approve(address, uint256)` |

All Explorer component paths are relative to `/git/edgeandnode/graph-explorer/graph-explorer/src/`.

## Implementation Approach

### Override Pattern

Add as a profiled service in `docker-compose.yaml`:

```yaml
# profiles: [explorer]
```

### Docker Compose Override

```yaml
services:
  graph-explorer:
    build:
      context: /git/edgeandnode/graph-explorer/graph-explorer
      dockerfile: Dockerfile
    ports:
      - "${EXPLORER_PORT:-3001}:3000"
    environment:
      - ENVIRONMENT=local
      - DEFAULT_CHAIN_NAME=hardhat
      - GRAPH_NETWORK_ID=1337
      - IS_TESTNET=true
    depends_on:
      ready:
        condition: service_completed_successfully
```

### Configuration Challenges

1. **Chain configuration**: Explorer expects Ethereum/Arbitrum chains. Local network uses hardhat (chainId 1337). May need chain config overrides or patches.

2. **Contract addresses**: Explorer resolves addresses from `@graphprotocol/address-book`. Local network deploys fresh addresses each time. Need to either:
   - Override address resolution at runtime
   - Build with local addresses baked in
   - Patch the address-book module

3. **Private npm dependencies**: `@edgeandnode/gds` and `@edgeandnode/graph-auth-kit` require npm authentication. The Dockerfile uses `.npmrc` secret mounting.

4. **Wallet connection**: MetaMask or similar needs to connect to the local hardhat chain (chainId 1337, RPC at localhost:8545).

### Complexity Assessment

| Aspect             | Difficulty  | Notes                          |
| ------------------ | ----------- | ------------------------------ |
| Docker build       | Low         | Dockerfile exists, port 3000   |
| Chain config       | Medium      | Needs hardhat chain support    |
| Address resolution | Medium-High | Fresh addresses per deployment |
| npm auth for build | Low         | `.npmrc` pattern exists        |
| Wallet integration | Medium      | MetaMask + hardhat chain       |
| Overall            | Medium      | Not blocking, but non-trivial  |

## Approach

### Phase 1: Investigate Feasibility

- [ ] Attempt local Docker build with npm auth
- [ ] Identify all hardcoded chain/network assumptions
- [ ] Test if address-book can be overridden at runtime
- [ ] Document blockers

### Phase 2: Minimal Integration

- [ ] Add graph-explorer service to `docker-compose.yaml` with `profiles: [explorer]`
- [ ] Configure for local hardhat chain
- [ ] Verify read-only operations work (view indexers, allocations, subgraphs)

### Phase 3: Full Integration

- [ ] Enable wallet connection to local chain
- [ ] Test write operations (delegate, signal, stake) via UI
- [ ] Document setup in README

## Value Assessment

**For testing**: Medium — test automation uses `cast send` regardless; Explorer adds visual verification but isn't required for scripted tests.

**For development**: High — seeing protocol state visually accelerates debugging and makes the local network more approachable.

**For documentation**: High — can reference exact UI flows and screenshot expected states.

**Recommendation**: Worth pursuing but not a strict dependency for test automation. The contract call reference table above (linking UI components to `cast` equivalents) bridges the gap for scripted tests.
