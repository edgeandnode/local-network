#!/bin/bash
set -eu

# Copy source to writable working directory (source mount is :ro).
# /app must be created here explicitly — before commit 3e9e76a the
# iisa-scores volume mount implicitly created /app/scores (and therefore
# /app), but that mount was removed when the cronjob stopped writing
# scores to disk.
mkdir -p /app
cp -r /opt/source/* /app/

cd /app

# Install dependencies
uv pip install --system -r requirements.txt

# Generate protobuf code
protoc -I proto --python_out=. proto/gateway_queries.proto

echo "=== Running IISA scoring (one-shot) ==="
echo "  Scores file: ${SCORES_FILE_PATH:-/app/scores/indexer_scores.json}"

exec python main.py
