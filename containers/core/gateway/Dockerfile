# check=skip=InvalidDefaultArgInFrom
ARG GATEWAY_VERSION

# Build environment — deps only, not used by the runtime image below.
# Built manually via `docker build --target build-env` as a dev builder
# for compiling a local gateway binary; see compose/dev/gateway.yaml.
FROM rust:1-slim-bookworm AS build-env
RUN apt-get update \
    && apt-get install -y clang cmake git libsasl2-dev libssl-dev pkg-config protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /opt

# Runtime: prebuilt gateway image wrapped with local-network's run.sh
FROM ghcr.io/edgeandnode/graph-gateway:${GATEWAY_VERSION}

# Tools needed by run.sh (config generation, wait_for_gql)
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl jq ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Upstream ENTRYPOINT is target/release/graph-gateway relative to /opt/gateway;
# expose on PATH so run.sh can invoke `graph-gateway` directly.
RUN ln -sf /opt/gateway/target/release/graph-gateway /usr/local/bin/graph-gateway

WORKDIR /opt
COPY ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
