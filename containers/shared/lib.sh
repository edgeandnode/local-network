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
       && [ -f /opt/config/tap-contracts.json ] \
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
