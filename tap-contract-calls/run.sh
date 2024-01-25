#!/bin/sh
set -euf

. ./.env

echo "awaiting scalar-tap-contracts"
until curl -s "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done
tap_contracts="$(curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/scalar_tap_contracts")"
export escrow="$(echo "${tap_contracts}" | jq -r '.escrow')"
echo "escrow=${escrow}"

python contract-calls.py "$escrow"