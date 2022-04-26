#!/bin/sh
. ./prelude.sh

docker_run ipfs \
  -p "${IPFS_PORT}:5001" \
  ipfs/go-ipfs:master
