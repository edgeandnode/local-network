#!/bin/bash
source .env
[ -f .env.local ] && source .env.local
address_to_query="${ACCOUNT0_ADDRESS}"
token_address=$(jq -r '."1337".L2GraphToken.address' horizon.json)
rpc_url="http://${CHAIN_HOST:-localhost}:${CHAIN_RPC_PORT}"
cast call --trace "$token_address" "balanceOf(address)(uint256)" "$address_to_query" --rpc-url "$rpc_url"
cast balance $address_to_query --rpc-url "$rpc_url"
