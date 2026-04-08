#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$REPO_ROOT/.env"
[ -f "$REPO_ROOT/.env.local" ] && source "$REPO_ROOT/.env.local"
source "$REPO_ROOT/shared/lib.sh"

address_to_query="${ACCOUNT0_ADDRESS}"
token_address=$(contract_addr L2GraphToken.address horizon)
rpc_url="http://${CHAIN_HOST:-localhost}:${CHAIN_RPC_PORT}"
cast call --trace "$token_address" "balanceOf(address)(uint256)" "$address_to_query" --rpc-url "$rpc_url"
cast balance $address_to_query --rpc-url "$rpc_url"
