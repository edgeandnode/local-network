# Task: Add Curation Signal to Local Network Setup

> Created: 2026-02-20
> Status: RESOLVED (2026-02-22) — implemented in `start-indexing/run.sh` and `graph-contracts/run.sh`

## Problem

BaselineTestPlan test 4.1 filters for `signalledTokens_not: 0` and returns empty on the local network because no curation signal is added during setup. This means any test that depends on curation data (signal amounts, curator entities, deployment filtering by signal) cannot run.

## Objective

Add curation signal to deployed subgraphs as part of the standard `start-indexing` setup flow, so the local network starts with realistic curation state.

## Scope

Small change (~20-30 lines) in `start-indexing/run.sh`. No new services, no new containers.

## Implementation

### Contracts

| Contract | Config file | Key |
|----------|------------|-----|
| L2Curation | `subgraph-service.json` | `.["1337"].L2Curation.address` |
| L2GraphToken | `horizon.json` | `.["1337"].L2GraphToken.address` |
| L2GNS | `subgraph-service.json` | `.["1337"].L2GNS.address` |

Addresses resolved via `contract_addr` helper in [containers/shared/lib.sh](../../../containers/shared/lib.sh).

### Insertion Point

In [start-indexing/run.sh](../../../start-indexing/run.sh), after GNS publishing (line 74) and before setting indexing rules (line 76):

```
line 54-74:  Publish subgraphs to GNS
line ??:     << ADD CURATION SIGNAL HERE >>
line 76-80:  Set indexing rules
```

### Steps

For each deployed subgraph (network, tap, block_oracle):

1. **Convert deployment IPFS hash to bytes32** (already done for GNS publishing — reuse `dep_hex`)

2. **Approve L2Curation to spend GRT**:
   ```bash
   cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
     --confirmations=0 --mnemonic="${MNEMONIC}" \
     "${grt}" 'approve(address,uint256)' "${curation}" "${SIGNAL_AMOUNT}"
   ```

3. **Mint signal via L2Curation**:
   ```bash
   cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" \
     --confirmations=0 --mnemonic="${MNEMONIC}" \
     "${curation}" 'mint(bytes32,uint256,uint256)(uint256,uint256)' \
     "0x${dep_hex}" "${SIGNAL_AMOUNT}" "0"
   ```

### Parameters

- **Curator account**: ACCOUNT0 (`0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`) — same account that publishes subgraphs
- **Signal amount**: 1000 GRT per subgraph (1000000000000000000000 wei) — enough to be meaningful, small relative to total supply
- **Min signal out**: 0 (no slippage protection needed on local network)

### Graph Explorer UI Equivalent

In Graph Explorer, this is the "Signal" action on a subgraph detail page:

| Explorer component | Contract call |
|---|---|
| [SignalForm.tsx:238-257](../../../) `onSignal()` — version signal path | `L2Curation.mint(deploymentId, amount, minSignal)` |
| [SignalForm.tsx:238-257](../../../) `onSignal()` — named signal path | `L2GNS.mintSignal(subgraphId, amount, minNameSignal)` |

For local network setup, the direct `L2Curation.mint()` call is simpler since we have deployment IDs directly and don't need NFT subgraph IDs.

### Verification

After signal is added, this query should return results:

```graphql
{
  subgraphDeployments(where: { signalledTokens_not: "0" }) {
    ipfsHash
    signalledTokens
    curatorSignals {
      curator { id }
      signal
      signalledTokens
    }
  }
}
```

### Idempotency

Check `signalledTokens` before minting — if already non-zero, skip. Follows the same pattern used for GNS publishing (check `subgraph_count` before publishing).

## Dependencies

None. All contracts already deployed. ACCOUNT0 already has GRT from protocol initialization.

## Affected Tests

- BaselineTestPlan 4.1: `subgraphDeployments(where: { signalledTokens_not: 0 })` — currently returns empty, will return data
- Any future Layer 2 tests involving curation operations
- Enables testing of curation-dependent reward calculations

## Files to Modify

| File | Change |
|------|--------|
| `start-indexing/run.sh` | Add curation signal block after GNS publishing |
| `scripts/test-baseline-state.sh` | Add check for `signalledTokens` non-zero |
