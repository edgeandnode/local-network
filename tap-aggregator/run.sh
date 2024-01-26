#!/bin/sh
set -eufx

if [ ! -d "build/semiotic-ai/timeline-aggregation-protocol" ]; then
  mkdir -p build/semiotic-ai/timeline-aggregation-protocol
  git clone git@github.com:semiotic-ai/timeline-aggregation-protocol build/semiotic-ai/timeline-aggregation-protocol --branch main
fi

. ./.env


cd build/semiotic-ai/timeline-aggregation-protocol

cargo run -p tap_aggregator -- \
  --private-key ${GATEWAY_SENDER_SECRET_KEY} \
  --port ${TAP_AGGREGATOR}
