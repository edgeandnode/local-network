#!/bin/bash
set -eu

# Build indexer-service-rs from source if mounted
if [ -d /opt/source ]; then
  echo "Building indexer-service-rs from local source..."
  cd /opt/source
  cargo build --release --bin indexer-service-rs
  cp target/release/indexer-service-rs /usr/local/bin/
  cd /opt
fi

# Run the original run.sh
exec /opt/run.sh
