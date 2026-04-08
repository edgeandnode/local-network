#!/bin/bash
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$REPO_ROOT/.env"
[ -f "$REPO_ROOT/.env.local" ] && source "$REPO_ROOT/.env.local"
source "$REPO_ROOT/shared/lib.sh"

deployment=$1
if [ -z "$deployment" ]; then
  echo "Usage: $0 <deployment_hash>"
  echo "  e.g.: $0 QmXyz..."
  exit 1
fi
CHAIN_HOST="${CHAIN_HOST:-localhost}"
INDEXER_AGENT_HOST="${INDEXER_AGENT_HOST:-localhost}"

echo "deployment=${deployment}"
deployment_hex="$(ipfs_hash_to_hex "$deployment")"

echo "deployment_hex=${deployment_hex}"
gns="$(contract_addr L2GNS.address subgraph-service)"

# https://github.com/graphprotocol/contracts/blob/3eb16c80d4652c238d3e6b2c396da712af5072b4/packages/sdk/src/deployments/network/actions/gns.ts#L38
cast send --rpc-url="http://${CHAIN_HOST}:${CHAIN_RPC_PORT}" --confirmations=0 --mnemonic="${MNEMONIC}" \
  "${gns}" 'publishNewSubgraph(bytes32,bytes32,bytes32)' \
  "0x${deployment_hex}" \
  '0x0000000000000000000000000000000000000000000000000000000000000000' \
  '0x0000000000000000000000000000000000000000000000000000000000000000'