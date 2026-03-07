#!/bin/bash
set -eu
. /opt/config/.env

cd /opt/source

# Install dependencies with uv
uv pip install --system -e .

echo "=== Starting IISA service ==="
echo "  Host: 0.0.0.0"
echo "  Port: 8080"

export IISA_HOST="0.0.0.0"
export IISA_PORT="8080"
export IISA_LOG_LEVEL="${IISA_LOG_LEVEL:-INFO}"

exec uvicorn iisa.iisa_http_endpoints:app --host 0.0.0.0 --port 8080 --reload
