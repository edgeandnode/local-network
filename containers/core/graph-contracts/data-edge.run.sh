#!/bin/bash
set -eu
. /opt/config/.env
. /opt/shared/lib.sh

# -- Ensure config file exists (empty JSON on first run) --
[ -f /opt/config/block-oracle.json ] || echo '{}' > /opt/config/block-oracle.json

echo "==== DataEdge contract deploy ===="

# -- Idempotency check --
skip=false
data_edge=$(jq -r '."1337".DataEdge // empty' /opt/config/block-oracle.json 2>/dev/null || true)
if [ -n "$data_edge" ]; then
  code_check=$(cast code --rpc-url="http://chain:${CHAIN_RPC_PORT}" "$data_edge" 2>/dev/null || echo "0x")
  if [ "$code_check" != "0x" ]; then
    echo "DataEdge contract already deployed at $data_edge"
    echo "SKIP: deploy"
    skip=true
  else
    echo "DataEdge address stale (no code at $data_edge), redeploying..."
  fi
fi

if [ "$skip" = "false" ]; then
  cd /opt/contracts-data-edge/packages/data-edge
  export MNEMONIC="${MNEMONIC}"
  sed -i "s/myth like bonus scare over problem client lizard pioneer submit female collect/${MNEMONIC}/g" hardhat.config.ts
  npx hardhat data-edge:deploy --contract EventfulDataEdge --deploy-name EBO --network ganache | tee deploy.txt
  data_edge="$(grep 'contract: ' deploy.txt | awk '{print $3}')"

  echo "=== Data edge deployed at: $data_edge ==="

  cat <<ADDR_EOF > /opt/config/block-oracle.json
{
  "1337": {
    "DataEdge": "$data_edge"
  }
}
ADDR_EOF

  # Register network in DataEdge
  output=$(cast send --rpc-url="http://chain:${CHAIN_RPC_PORT}" --confirmations=0 --mnemonic="${MNEMONIC}" \
    "${data_edge}" \
    '0xa1dce3320000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000f030103176569703135353a313333370000000000000000000000000000000000' 2>&1)
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "Error during cast send: $output" | tee -a error.log
  else
    echo "$output"
  fi
fi

echo "==== DataEdge contract deploy complete ===="

# Optional: keep container running for debugging
if [ -n "${KEEP_CONTAINER_RUNNING:-}" ]; then
  tail -f /dev/null
fi
