---
name: fund-indexers
description: Deposit GRT into PaymentsEscrow for each indexer so DIPs collect() calls succeed. Use when testing the DIPs payment flow, when collect() reverts with PaymentsEscrowInsufficientBalance, before sending indexing requests for the first time on a fresh deploy, or when the user asks to fund indexers, top up escrow, or top up the consumer side of DIPs.
argument-hint: "[amount-in-grt]"
---

# Fund Indexers for DIPs Collection

Deposit GRT into `PaymentsEscrow` with `(payer=ACCOUNT0, collector=RecurringCollector, receiver=<indexer>)` for each registered indexer, so DIPs `collect()` calls don't revert with `PaymentsEscrowInsufficientBalance`.

## Why this is needed

In production, the consumer (e.g., Subgraph Studio) calls `PaymentsEscrow.deposit()` before issuing DIPs offers. In local-network nobody plays the consumer's escrow-funding role by default — there is no `dips-escrow-manager` init container equivalent for the `RecurringCollector` side, only the existing `graph-tally-escrow-manager` which funds `GraphTallyCollector` (TAP query payments).

Without this skill, every DIPs `collect()` reverts with `PaymentsEscrowInsufficientBalance(balance: 0, minBalance: ...)`, indexers retry forever, `tokensCollected` stays 0, and the payment side of the DIPs flow can never be observed end-to-end.

This skill plays the consumer role from ACCOUNT0 (which is also dipper's signer / the on-chain payer). The deposit is keyed by `(payer, collector, receiver)` — a single balance per indexer covers all agreements between that payer and that indexer, no matter how many or which deployments. There is no per-agreement top-up step.

## Targets

Runs on the `lnet-test` VM via SSH. Requires Foundry's `cast` on the VM (installed once by the add-indexers skill's prerequisites step).

For a local-only docker setup, drop the `ssh lnet-test` wrapper.

## Argument

Default deposit is **1,000,000 GRT** per indexer. Override with the first arg: `/fund-indexers 500000` deposits 500K GRT each.

The default is intentionally large — for test purposes the exact number doesn't matter, it just needs to comfortably exceed any conceivable `collect()` amount during a session.

## Steps

The whole flow is a single ssh-bash heredoc that:

1. Resolves contract addresses from horizon.json (GRT, PaymentsEscrow, RecurringCollector).
2. Queries the network subgraph for current indexer addresses (anyone registered with a non-empty URL).
3. Approves `PaymentsEscrow` to pull GRT from ACCOUNT0 (max approval, idempotent — once-per-session in practice).
4. Loops the indexers and calls `PaymentsEscrow.deposit(RC, indexer, amount)` for each, signed by ACCOUNT0.
5. Reads back `getBalance(ACCOUNT0, RC, indexer)` for each to confirm.

```bash
AMOUNT_GRT=${ARG1:-1000000}
ssh lnet-test "bash -s -- $AMOUNT_GRT" <<'REMOTE'
set -eo pipefail
AMOUNT_GRT=$1
AMOUNT_WEI=$(python3 -c "print($AMOUNT_GRT * 10**18)")

GRT=$(docker exec graph-node cat /opt/config/horizon.json | jq -r '."1337".L2GraphToken.address')
PE=$(docker exec graph-node cat /opt/config/horizon.json | jq -r '."1337".PaymentsEscrow.address')
RC=$(docker exec graph-node cat /opt/config/horizon.json | jq -r '."1337".RecurringCollector.address')
ACCOUNT0=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
SECRET=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
RPC=http://localhost:8545

# Run cast send and fail loud if the tx didn't reach "status 1 (success)".
# The previous pattern (`cast send ... 2>&1 | grep -E '...' | head -2`)
# silently exited 0 when cast failed or returned no success line, because
# head's exit code masked everything earlier in the pipeline.
send_or_die() {
  local label=$1; shift
  local out
  if ! out=$(cast send "$@" --rpc-url "$RPC" --private-key "$SECRET" 2>&1); then
    echo "[$label] cast send failed:"; echo "$out"; exit 1
  fi
  if ! grep -q 'status .*1 (success)' <<<"$out"; then
    echo "[$label] cast send returned no success line:"; echo "$out"; exit 1
  fi
  grep -E 'status|transactionHash' <<<"$out" | head -2
}

echo "GRT=$GRT  PaymentsEscrow=$PE  RecurringCollector=$RC"
echo "depositing $AMOUNT_WEI wei ($AMOUNT_GRT GRT) per indexer"

INDEXERS=$(curl -s -X POST -H "Content-Type: application/json" \
  -d '{"query":"{ indexers(where: { url_not: \"\" }) { id } }"}' \
  http://localhost:8000/subgraphs/name/graph-network \
  | python3 -c "import json,sys; print(' '.join(i['id'] for i in json.load(sys.stdin)['data']['indexers']))")
echo "indexers: $INDEXERS"

echo "--- approve(PaymentsEscrow, max) ---"
send_or_die approve "$GRT" 'approve(address,uint256)' "$PE" \
  0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff

for I in $INDEXERS; do
  echo "--- deposit for $I ---"
  send_or_die "deposit/$I" "$PE" 'deposit(address,address,uint256)' "$RC" "$I" "$AMOUNT_WEI"
done

echo "--- final balances (wei) ---"
for I in $INDEXERS; do
  BAL=$(cast call "$PE" 'getBalance(address,address,address)(uint256)' "$ACCOUNT0" "$RC" "$I" --rpc-url "$RPC")
  printf "%-44s  %s\n" "$I" "$BAL"
done
REMOTE
```

Substitute `$ARG1` with the user-provided argument (or omit for the default 1,000,000).

## Verification after running

Once the deposits land, the indexer-agents' throttled `collectAgreementPayments` retry should succeed within the next ~60s (the agents log "1 of N agreement(s) ready for collection" and then submit the actual collect tx — previously they were getting `PaymentsEscrowInsufficientBalance`, now they should get tx hashes).

Check on the indexing-payments subgraph that `tokensCollected > 0` and that `IndexingFeeCollection` entities now exist:

```bash
ssh lnet-test 'curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"query\":\"{ indexingAgreements(orderBy: lastStateChangeBlock, orderDirection: desc, first: 5) { id state tokensCollected collections { transactionHash tokensCollected } } }\"}" \
  http://localhost:8000/subgraphs/name/indexing-payments'
```

## Notes

- **Idempotent**: re-running just adds more GRT to the existing balance — no state corruption, no double-spend risk.
- **One deposit per indexer**, not per agreement — the on-chain balance is keyed by `(payer, collector, receiver)`. All of ACCOUNT0's DIPs agreements with one indexer draw from the same pool, regardless of which deployment they're for.
- **Permanent fix instead of this skill**: add a `dips-escrow-manager` init container modeled after `graph-tally-escrow-manager`, run automatically at stack-up. This skill is the operator-driven equivalent useful before that container exists, or when you want to top up specific amounts outside the init flow.
- **The approve step is one-time per session** in practice: max approval persists until used or revoked. Re-running the skill does send the approve tx again (harmless, gas-cheap on hardhat).
