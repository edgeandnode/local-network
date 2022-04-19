#!/bin/sh
. ./prelude.sh

docker_run redpanda \
  -p "${REDPANDA_PORT}:9092" \
  -p 9644:9644 \
  docker.vectorized.io/vectorized/redpanda:latest \
  redpanda start \
    --overprovisioned \
    --smp 1  \
    --memory 1G \
    --reserve-memory 0M \
    --node-id 0 \
    --check=false
