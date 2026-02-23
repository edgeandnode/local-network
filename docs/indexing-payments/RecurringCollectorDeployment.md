# RecurringCollector Deployment — Outstanding Work

Status: **not yet deployed** in local network or production.

Dipper references `recurring_collector` in its config but currently uses the null address.
The contract source exists in the `rem-baseline-merge` contracts branch but is not wired
into any deployment path.

## Contracts repo (`graphprotocol/contracts`)

### 1. Ignition modules (local network / Hardhat)

The `deploy:protocol` Hardhat task deploys SubgraphService via Ignition modules.
The SubgraphService Solidity constructor now expects a 5th parameter (`recurringCollector`),
but the Ignition module still passes only 4 — deployment will fail on the current baseline.

Commit `f3fdc5114` ("feat: add RecurringCollector, indexingFeesCut, and library linking to
ignition deployment") adds the required Ignition wiring but is **not merged** into the
baseline branch. It needs to be cherry-picked or merged. That commit adds:

- `packages/horizon/ignition/modules/core/RecurringCollector.ts`
- RecurringCollector import in `core.ts`
- 5th constructor arg in `SubgraphService.ts` Ignition module
- Config patching in `deploy.ts` task

### 2. Deployment package (production / testnet)

`packages/deployment/deploy/service/subgraph/01_deploy.ts` constructs SubgraphService with
4 args (Controller, DisputeManager, GraphTallyCollector, Curation). Once the contract
requires 5, this script must also be updated:

- Add RecurringCollector to the contract registry or fetch it as a dependency
- Deploy RecurringCollector (or reference an existing deployment) before SubgraphService
- Pass `recurringCollectorAddress` as the 5th constructor arg
- Update `02_upgrade.ts` if the upgrade path needs the new implementation

`Directory.sol` gains an immutable `RECURRING_COLLECTOR` field and a
`recurringCollector()` getter. Since Solidity immutables are embedded in bytecode
(not storage), this does not break storage layout — it's a standard proxy
implementation upgrade via `upgradeAndCall()`.

## Local network (`rem-local-network`)

After the contracts branch includes RecurringCollector in Ignition:

1. **`.env`** — update `CONTRACTS_COMMIT` to the new contracts commit
2. **`containers/core/graph-contracts/run.sh`** — extract RecurringCollector address from
   the deployed address book (likely `horizon.json`)
3. **`containers/indexing-payments/dipper/run.sh`** — replace null address with:
   ```bash
   recurring_collector=$(contract_addr RecurringCollector.address horizon)
   ```

## Dipper

No code changes needed — Dipper already has full RCA support (EIP-712 signing, agreement
lifecycle, chain listener, on-chain cancellation). It uses hand-written `sol!` macro
bindings, not a contracts submodule, so no dependency to bump. It just needs the real
contract address in its config.

## Summary of blocking order

```
contracts: merge Ignition commit (f3fdc5114) into baseline
    ↓
contracts: update deployment package for 5-arg SubgraphService
    ↓
local-network: bump CONTRACTS_COMMIT, wire RecurringCollector address
    ↓
dipper config picks up real address — RCA functional end-to-end
```
