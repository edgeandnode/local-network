ARG INDEXER_TAP_AGENT_VERSION

## Rust builder image
FROM rust:1-slim AS rust-builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        pkg-config \
        protobuf-compiler \
        libssl-dev \
        libsasl2-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

COPY source ./

# Force SQLx to use the offline mode to statically check the database queries against
# the prepared files in the `.sqlx` directory.
ENV SQLX_OFFLINE=true

RUN --mount=type=cache,sharing=locked,id=cargo-registry,target=/usr/local/cargo/registry \
    --mount=type=cache,id=indexer-tap-agent-build-cache,target=/opt/target \
    cargo build --bin indexer-tap-agent \
  && cp target/debug/indexer-tap-agent /opt/indexer-tap-agent


## Wrapper development image
FROM debian:bookworm-slim AS wrapper-dev

RUN apt-get update \
    && apt-get install -y curl jq \
    && rm -rf /var/lib/apt/lists/*

# Copy the built binary from the rust builder image
COPY --from=rust-builder /opt/indexer-tap-agent /usr/local/bin/indexer-tap-agent

COPY ./run.sh /opt/run.sh

ENTRYPOINT bash -cl /opt/run.sh

## Wrapper image
FROM ghcr.io/graphprotocol/indexer-tap-agent:${INDEXER_TAP_AGENT_VERSION} AS wrapper
RUN apt-get update \
    && apt-get install -y git jq \
    && rm -rf /var/lib/apt/lists/*

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
