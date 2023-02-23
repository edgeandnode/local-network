#!/bin/sh
. ./prelude.sh

github_clone edgeandnode/graph-gateway

cd build/edgeandnode/graph-gateway
cargo build
cd -

await_ready graph-subgraph
await "test -f build/studio-admin-auth.txt"

export STUDIO_AUTH=$(cat build/studio-admin-auth.txt)
envsubst <gateway.toml >build/gateway.toml

cd build/edgeandnode/graph-gateway

export RUST_LOG=info,graph_gateway=trace
cargo run --bin graph-gateway ../../gateway.toml
