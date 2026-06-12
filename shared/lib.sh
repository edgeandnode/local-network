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

# kafka_topic BASE
# Returns BASE with _${KAFKA_TOPIC_ENVIRONMENT} appended when set, or BASE unchanged.
# Mirrors gateway's kafka_topic_environment config.
kafka_topic() {
  _env="${KAFKA_TOPIC_ENVIRONMENT:-}"
  _env=$(printf '%s' "$_env" | tr -d '[:space:]')
  if [ -n "$_env" ]; then
    printf '%s_%s' "$1" "$_env"
  else
    printf '%s' "$1"
  fi
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
