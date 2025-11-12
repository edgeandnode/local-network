#!/bin/sh
set -e

# Get the directory where this script is located
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Create the local directory if it doesn't exist
mkdir -p "$SCRIPT_DIR/local"

# Copy all template files to local if they don't exist
for file in "$SCRIPT_DIR/templates"/*; do
  filename=$(basename "$file")
  if [ ! -f "$SCRIPT_DIR/local/$filename" ]; then
    echo "Copying $SCRIPT_DIR/templates/$filename to $SCRIPT_DIR/local/$filename"
    cp "$file" "$SCRIPT_DIR/local/$filename"
  fi
done

echo "Config files initialized successfully"
