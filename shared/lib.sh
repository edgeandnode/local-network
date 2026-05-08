#!/bin/sh
# Shared shell utilities for local-network (container services and host scripts)

require_jq() {
  _val=$(jq -r "$1 // empty" ${2:+"$2"})
  if [ -z "$_val" ]; then
    echo "Error: $1 not found in ${2:-stdin}" >&2
    exit 1
  fi
  printf '%s' "$_val"
}

# contract_addr CONTRACT_NAME ADDRESS_BOOK
# Gets a contract address from a config file
# Supports both host and container execution contexts.
# Example: contract_addr L2GraphToken.address horizon
contract_addr() {
  if [ -d "/opt/config" ]; then
    require_jq ".\"1337\".$1" "/opt/config/$2.json"
  else
    docker exec graph-node cat "/opt/config/$2.json" \
      | require_jq ".\"1337\".$1"
  fi
}

# base58_to_hex INPUT
# Decodes a base58 string to hex. Uses bc for big number arithmetic.
# Example: base58_to_hex "QmXyz..." -> "1220abcd..."
base58_to_hex() {
  # Disable trace to avoid noisy output
  { _xtrace_was_set=1; set +x; } 2>/dev/null || _xtrace_was_set=0

  _input="$1"
  _alphabet="123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
  _decimal=0

  # Convert base58 to decimal
  _i=0
  while [ "$_i" -lt "${#_input}" ]; do
    _char=$(echo "$_input" | cut -c$((_i + 1)))
    # Find index in alphabet
    _idx=0
    while [ "$_idx" -lt 58 ]; do
      _achar=$(echo "$_alphabet" | cut -c$((_idx + 1)))
      if [ "$_char" = "$_achar" ]; then
        break
      fi
      _idx=$((_idx + 1))
    done
    _decimal=$(echo "$_decimal * 58 + $_idx" | bc)
    _i=$((_i + 1))
  done

  # Convert decimal to hex
  _hex=$(echo "obase=16; $_decimal" | bc | tr -d '\\\n')

  # Pad to even length
  if [ $((${#_hex} % 2)) -eq 1 ]; then
    _hex="0$_hex"
  fi

  # Handle leading zeros (each leading '1' in base58 = 0x00 byte)
  _leading=""
  _j=0
  while [ "$_j" -lt "${#_input}" ]; do
    _char=$(echo "$_input" | cut -c$((_j + 1)))
    if [ "$_char" != "1" ]; then
      break
    fi
    _leading="${_leading}00"
    _j=$((_j + 1))
  done

  _result=$(printf '%s%s' "$_leading" "$_hex" | tr '[:upper:]' '[:lower:]')

  # Restore trace if it was set
  [ "$_xtrace_was_set" = 1 ] && set -x 2>/dev/null
  printf '%s' "$_result"
}

# ipfs_hash_to_hex IPFS_HASH
# Converts an IPFS CIDv0 hash (Qm...) to the 32-byte hex hash.
# Strips the multihash prefix (1220 for sha256).
# Example: ipfs_hash_to_hex "QmXyz..." -> "abcd1234..."
ipfs_hash_to_hex() {
  _full=$(base58_to_hex "$1")
  # Skip first 4 hex chars (2 bytes: 0x1220 multihash prefix)
  printf '%s' "$_full" | cut -c5-
}

# wait_for_gql URL QUERY JQ_FILTER [TIMEOUT]
# Polls a GraphQL endpoint until JQ_FILTER returns a non-empty value.
# Prints the value on success, exits 1 on timeout.
wait_for_gql() {
  _url="$1" _query="$2" _filter="$3" _timeout="${4:-120}" _elapsed=0
  while [ "$_elapsed" -lt "$_timeout" ]; do
    _val=$(curl -sf "$_url" \
      -H 'content-type: application/json' \
      -d "{\"query\": \"$_query\"}" 2>/dev/null \
      | jq -r "$_filter // empty" 2>/dev/null || true)
    if [ -n "$_val" ]; then
      printf '%s' "$_val"
      return 0
    fi
    sleep 2
    _elapsed=$((_elapsed + 2))
  done
  echo "Error: timed out waiting for $_url after ${_timeout}s" >&2
  exit 1
}

wait_for_rpc() {
  echo "Waiting for chain RPC at http://chain:${CHAIN_RPC_PORT}..."
  if command -v cast > /dev/null 2>&1; then
    until cast block-number --rpc-url="http://chain:${CHAIN_RPC_PORT}" > /dev/null 2>&1; do
      sleep 2
    done
  else
    until curl -sf "http://chain:${CHAIN_RPC_PORT}" -X POST \
      -H 'content-type: application/json' \
      -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' > /dev/null 2>&1; do
      sleep 2
    done
  fi
  echo "Chain RPC available"
}

# wait_for_url URL [TIMEOUT]
# Polls a URL until it returns a successful response.
wait_for_url() {
  _wfu_url="$1" _wfu_timeout="${2:-300}" _wfu_elapsed=0
  echo "Waiting for ${_wfu_url}..." >&2
  while [ "$_wfu_elapsed" -lt "$_wfu_timeout" ]; do
    if curl -sf "$_wfu_url" > /dev/null 2>&1; then
      echo "${_wfu_url} is ready" >&2
      return 0
    fi
    sleep 2
    _wfu_elapsed=$((_wfu_elapsed + 2))
  done
  echo "Error: timed out waiting for ${_wfu_url} after ${_wfu_timeout}s" >&2
  return 1
}

# wait_for_config [TIMEOUT]
# Polls until the config volume has all contract address files populated by graph-contracts.
wait_for_config() {
  _wfc_timeout="${1:-300}" _wfc_elapsed=0
  echo "Waiting for contract config..." >&2
  while [ "$_wfc_elapsed" -lt "$_wfc_timeout" ]; do
    if [ -f /opt/config/horizon.json ] && jq -e '.["1337"]' /opt/config/horizon.json > /dev/null 2>&1 \
       && [ -f /opt/config/subgraph-service.json ]; then
      echo "Contract config available" >&2
      return 0
    fi
    sleep 2
    _wfc_elapsed=$((_wfc_elapsed + 2))
  done
  echo "Error: timed out waiting for contract config after ${_wfc_timeout}s" >&2
  return 1
}

retry_cmd() {
  _rc_max="${1}"; shift
  _rc_delay="${1}"; shift
  _rc_attempt=0
  while [ "$_rc_attempt" -lt "$_rc_max" ]; do
    _rc_attempt=$((_rc_attempt + 1))
    if "$@"; then
      return 0
    fi
    echo "Attempt $_rc_attempt/$_rc_max failed, retrying in ${_rc_delay}s..."
    sleep "$_rc_delay"
  done
  echo "Command failed after $_rc_max attempts: $*"
  return 1
}
