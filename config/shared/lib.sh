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
