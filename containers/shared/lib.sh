#!/bin/sh
# Shared shell utilities for local-network services

require_jq() {
  _val=$(jq -r "$1 // empty" "$2")
  if [ -z "$_val" ]; then
    echo "Error: $1 not found in $2" >&2
    exit 1
  fi
  printf '%s' "$_val"
}

contract_addr() {
  require_jq ".\"1337\".$1" "/opt/config/$2.json"
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
