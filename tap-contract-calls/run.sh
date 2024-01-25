#!/bin/sh
set -euf

. ./.env
until curl -s "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}" >/dev/null; do sleep 1; done

echo "awaiting scalar-tap-contracts"
tap_contracts="$(curl "http://${DOCKER_GATEWAY_HOST}:${CONTROLLER}/scalar_tap_contracts")"
export escrow="$(echo "${tap_contracts}" | jq -r '.escrow')"
echo "escrow=${escrow}"

python contract-calls.py "$escrow"
