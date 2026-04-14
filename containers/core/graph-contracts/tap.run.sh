#!/bin/bash
set -eu
. /opt/config/.env
. /opt/shared/lib.sh

# -- Ensure config file exists (empty JSON on first run) --
[ -f /opt/config/tap-contracts.json ] || echo '{}' > /opt/config/tap-contracts.json

echo "==== TAP contracts deploy ===="

# -- Idempotency check --
skip=false
escrow_address=$(jq -r '."1337".Escrow // empty' /opt/config/tap-contracts.json 2>/dev/null || true)
if [ -n "$escrow_address" ]; then
  code_check=$(cast code --rpc-url="http://chain:${CHAIN_RPC_PORT}" "$escrow_address" 2>/dev/null || echo "0x")
  if [ "$code_check" != "0x" ]; then
    echo "TAP contracts already deployed (Escrow at $escrow_address)"
    echo "SKIP: deploy"
    skip=true
  else
    echo "TAP contract addresses are stale (no code at Escrow $escrow_address), redeploying..."
  fi
fi

if [ "$skip" = "false" ]; then
  cd /opt/timeline-aggregation-protocol-contracts

  staking=$(contract_addr HorizonStaking.address horizon)
  graph_token=$(contract_addr L2GraphToken.address horizon)

  # Note: forge may output alloy log lines to stdout after the JSON; sed extracts only the JSON object
  forge create --broadcast --json --rpc-url="http://chain:${CHAIN_RPC_PORT}" --mnemonic="${MNEMONIC}" \
    src/AllocationIDTracker.sol:AllocationIDTracker \
    | tee allocation_tracker.json
  allocation_tracker="$(sed -n '/^{/,/^}/p' allocation_tracker.json | jq -r '.deployedTo')"

  forge create --broadcast --json --rpc-url="http://chain:${CHAIN_RPC_PORT}" --mnemonic="${MNEMONIC}" \
    src/TAPVerifier.sol:TAPVerifier --constructor-args 'TAP' '1' \
    | tee verifier.json
  verifier="$(sed -n '/^{/,/^}/p' verifier.json | jq -r '.deployedTo')"

  forge create --broadcast --json --rpc-url="http://chain:${CHAIN_RPC_PORT}" --mnemonic="${MNEMONIC}" \
    src/Escrow.sol:Escrow --constructor-args "${graph_token}" "${staking}" "${verifier}" "${allocation_tracker}" 10 15 \
    | tee escrow.json
  escrow="$(sed -n '/^{/,/^}/p' escrow.json | jq -r '.deployedTo')"

  cat <<EOF > /opt/config/tap-contracts.json
{
  "1337": {
    "AllocationIDTracker": "$allocation_tracker",
    "TAPVerifier": "$verifier",
    "Escrow": "$escrow"
  }
}
EOF
fi

echo "==== TAP contracts deploy complete ===="

# Optional: keep container running for debugging
if [ -n "${KEEP_CONTAINER_RUNNING:-}" ]; then
  tail -f /dev/null
fi
