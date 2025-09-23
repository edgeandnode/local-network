#!/bin/bash

# This script executes the Horizon Phase 4 upgrade step.
# Requirements: must be running local network with Horizon Phase 3 override.

set -e

echo "Executing Horizon Phase 4 upgrade..."

# Use docker compose run with --entrypoint to override the default entrypoint from Phase 3 override
docker compose run --rm --entrypoint bash graph-contracts -c \
    "cd /opt/contracts/packages/horizon \
    && npx hardhat deploy:migrate --network localNetwork --step 4 --patch-config"

echo "✅ Horizon Phase 4 upgrade completed successfully!"

echo "-- Notice about allocation expiry --"
echo "Protocol epochs have a duration of 1 epoch = 554 blocks."
echo "- Legacy allocations have a max allocation duration of 4 epochs before horizon (protocol parameter) and 28 epochs after horizon (hardcoded)."
echo "- Horizon allocations have a max allocation duration of 7200 seconds (protocol parameter) which translates to 1 epoch assuming 12 second block time (indexer-agent assumes as much)."