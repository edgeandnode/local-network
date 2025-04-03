## Rust builder image
FROM rust:1-slim AS rust-builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        pkg-config \
        protobuf-compiler \
        libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

COPY source ./

# Force SQLx to use the offline mode to statically check the database queries against
# the prepared files in the `.sqlx` directory.
ENV SQLX_OFFLINE=true

RUN --mount=type=cache,sharing=locked,id=cargo-registry,target=/usr/local/cargo/registry \
    --mount=type=cache,id=indexer-service-rs-build-cache,target=/opt/target \
    cargo build --bin indexer-service-rs \
  && cp target/debug/indexer-service-rs /opt/indexer-service-rs


## Wrapper development image
FROM debian:bookworm-slim AS wrapper-dev

RUN apt-get update \
    && apt-get install -y curl jq \
    && rm -rf /var/lib/apt/lists/*

# Copy the built binary from the rust builder image
COPY --from=rust-builder /opt/indexer-service-rs /usr/local/bin/indexer-service-rs

COPY ./run.sh /opt/run.sh

ENTRYPOINT bash -cl /opt/run.sh


## Wrapper image
FROM ghcr.io/graphprotocol/indexer-service-rs:v1.5.0 AS wrapper
RUN apt-get update \
    && apt-get install -y curl jq \
    && rm -rf /var/lib/apt/lists/*

COPY ./run.sh /opt/run.sh

ENTRYPOINT bash -cl /opt/run.sh