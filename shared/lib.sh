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
