#!/bin/bash
# View or change REO (Rewards Eligibility Oracle) contract configuration.
#
# Usage:
#   ./scripts/reo-config.sh                          # Show current config
#   ./scripts/reo-config.sh eligibility-period 300    # Set eligibility period to 5 minutes
#   ./scripts/reo-config.sh oracle-timeout 86400      # Set oracle update timeout to 1 day
#
# Common values:
#   Eligibility period:    300 (5min), 600 (10min), 3600 (1hr), 86400 (1day)
#   Oracle update timeout: 86400 (1day), 604800 (7days)
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load environment
# shellcheck source=../.env
. "$REPO_ROOT/.env"

RPC_URL="http://${CHAIN_HOST:-localhost}:${CHAIN_RPC_PORT}"

# Read REO contract address from config-local volume
REO_ADDRESS=$(docker exec graph-node cat /opt/config/issuance.json 2>/dev/null \
  | jq -r '.["1337"].RewardsEligibilityOracle.address // empty' 2>/dev/null || true)
if [ -z "$REO_ADDRESS" ]; then
  echo "ERROR: RewardsEligibilityOracle address not found."
  echo "  Is the local network running with the REO contract deployed?"
  exit 1
fi

# cast call returns e.g. "1209600 [1.209e6]" — strip the annotation
cast_uint() {
  echo "$1" | awk '{print $1}'
}

format_duration() {
  local secs=$1
  if [ "$secs" -ge 86400 ]; then
    echo "${secs}s ($(( secs / 86400 ))d $(( (secs % 86400) / 3600 ))h)"
  elif [ "$secs" -ge 3600 ]; then
    echo "${secs}s ($(( secs / 3600 ))h $(( (secs % 3600) / 60 ))m)"
  elif [ "$secs" -ge 60 ]; then
    echo "${secs}s ($(( secs / 60 ))m $(( secs % 60 ))s)"
  else
    echo "${secs}s"
  fi
}

show_config() {
  echo "=== REO Contract Configuration ==="
  echo "  Contract: $REO_ADDRESS"
  echo ""

  validation=$(cast call --rpc-url="$RPC_URL" \
    "$REO_ADDRESS" "getEligibilityValidation()(bool)" 2>/dev/null)
  echo "  Eligibility validation: $validation"

  period=$(cast_uint "$(cast call --rpc-url="$RPC_URL" \
    "$REO_ADDRESS" "getEligibilityPeriod()(uint256)" 2>/dev/null)")
  echo "  Eligibility period:    $(format_duration "$period")"

  timeout=$(cast_uint "$(cast call --rpc-url="$RPC_URL" \
    "$REO_ADDRESS" "getOracleUpdateTimeout()(uint256)" 2>/dev/null)")
  echo "  Oracle update timeout: $(format_duration "$timeout")"

  last_update=$(cast_uint "$(cast call --rpc-url="$RPC_URL" \
    "$REO_ADDRESS" "getLastOracleUpdateTime()(uint256)" 2>/dev/null)")
  if [ "$last_update" = "0" ]; then
    echo "  Last oracle update:    never"
  else
    now=$(date +%s)
    ago=$(( now - last_update ))
    echo "  Last oracle update:    $(format_duration "$ago") ago (timestamp $last_update)"
  fi
}

set_param() {
  local param_name=$1
  local setter=$2
  local getter=$3
  local new_value=$4

  current=$(cast_uint "$(cast call --rpc-url="$RPC_URL" \
    "$REO_ADDRESS" "${getter}()(uint256)" 2>/dev/null)")

  if [ "$current" = "$new_value" ]; then
    echo "$param_name is already $new_value"
    return
  fi

  echo "Setting $param_name: $(format_duration "$current") -> $(format_duration "$new_value")"
  cast send --rpc-url="$RPC_URL" --confirmations=0 \
    --private-key="$ACCOUNT0_SECRET" \
    "$REO_ADDRESS" "${setter}(uint256)" "$new_value"
  echo "Done."
}

case "${1:-}" in
  eligibility-period)
    if [ -z "${2:-}" ]; then
      echo "Usage: $0 eligibility-period <seconds>"
      echo "  e.g.: $0 eligibility-period 300   # 5 minutes"
      exit 1
    fi
    set_param "eligibility period" "setEligibilityPeriod" "getEligibilityPeriod" "$2"
    ;;
  oracle-timeout)
    if [ -z "${2:-}" ]; then
      echo "Usage: $0 oracle-timeout <seconds>"
      echo "  e.g.: $0 oracle-timeout 86400   # 1 day"
      exit 1
    fi
    set_param "oracle update timeout" "setOracleUpdateTimeout" "getOracleUpdateTimeout" "$2"
    ;;
  "")
    show_config
    ;;
  *)
    echo "Unknown command: $1"
    echo ""
    echo "Usage:"
    echo "  $0                              Show current config"
    echo "  $0 eligibility-period <secs>    Set eligibility period"
    echo "  $0 oracle-timeout <secs>        Set oracle update timeout"
    exit 1
    ;;
esac
