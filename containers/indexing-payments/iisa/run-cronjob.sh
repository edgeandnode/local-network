#!/bin/bash
set -eu

# Copy source to writable working directory (source mount is :ro)
cp -r /opt/source/* /app/

cd /app

# Install dependencies
uv pip install --system -r requirements.txt

# Generate protobuf code
protoc -I proto --python_out=. proto/gateway_queries.proto

echo "=== Starting IISA scoring service ==="
echo "  Scores file: ${SCORES_FILE_PATH:-/app/scores/indexer_scores.json}"
echo "  Interval: ${SCORING_INTERVAL:-86400}s"
echo "  HTTP port: ${SCORING_HTTP_PORT:-9090}"

exec python main.py
