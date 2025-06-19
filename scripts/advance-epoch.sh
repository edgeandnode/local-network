#!/bin/bash

# Get number of epochs to advance (default to 1 if not provided)
EPOCHS_TO_ADVANCE=${1:-1}

# Get the EpochManager contract address from horizon.json
EPOCH_MANAGER_ADDRESS=$(jq -r '."1337".EpochManager.address' horizon.json)

# Get current epoch
CURRENT_EPOCH=$(cast call $EPOCH_MANAGER_ADDRESS "currentEpoch()(uint256)" --rpc-url http://localhost:8545)

# Get epoch length
EPOCH_LENGTH=$(cast call $EPOCH_MANAGER_ADDRESS "epochLength()(uint256)" --rpc-url http://localhost:8545)

# Get current block number
CURRENT_BLOCK=$(cast block latest --rpc-url http://localhost:8545 | grep number | awk '{print $2}')

# Get current epoch block
CURRENT_EPOCH_BLOCK=$(cast call $EPOCH_MANAGER_ADDRESS "currentEpochBlock()(uint256)" --rpc-url http://localhost:8545)

# Calculate blocks until next epoch
BLOCKS_IN_CURRENT_EPOCH=$((CURRENT_BLOCK - CURRENT_EPOCH_BLOCK))
BLOCKS_TO_MINE=$((EPOCH_LENGTH - BLOCKS_IN_CURRENT_EPOCH + (EPOCH_LENGTH * (EPOCHS_TO_ADVANCE - 1))))

echo "Current epoch: $CURRENT_EPOCH"
echo "Epoch length: $EPOCH_LENGTH blocks"
echo "Current block: $CURRENT_BLOCK"
echo "Current epoch block: $CURRENT_EPOCH_BLOCK"
echo "Blocks in current epoch: $BLOCKS_IN_CURRENT_EPOCH"
echo "Advancing by $EPOCHS_TO_ADVANCE epoch(s)"
echo "Blocks to mine: $BLOCKS_TO_MINE"

# Mine blocks until next epoch using mine-block.sh
./scripts/mine-block.sh $BLOCKS_TO_MINE

# Verify we're in the next epoch
NEW_EPOCH=$(cast call $EPOCH_MANAGER_ADDRESS "currentEpoch()(uint256)" --rpc-url http://localhost:8545)
echo "New epoch: $NEW_EPOCH"
