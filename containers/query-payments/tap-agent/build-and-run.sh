#!/bin/bash
set -eu

# Build indexer-tap-agent from source if mounted
if [ -d /opt/source ]; then
  echo "Building indexer-tap-agent from local source..."
  cd /opt/source
  cargo build --release --bin indexer-tap-agent
  cp target/release/indexer-tap-agent /usr/local/bin/
  cd /opt
fi

# Run the original run.sh
exec /opt/run.sh
