#!/bin/bash
source .env
address_to_query="${ACCOUNT0_ADDRESS}"
token_address=$(jq -r '."1337".L2GraphToken.address' horizon.json)
rpc_url="http://127.0.0.1:8545"
cast call --trace "$token_address" "balanceOf(address)(uint256)" "$address_to_query" --rpc-url "$rpc_url"
cast balance $address_to_query --rpc-url http://127.0.0.1:8545
