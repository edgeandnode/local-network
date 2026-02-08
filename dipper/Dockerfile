## Rust builder
# Compile the Rust code
FROM rust:1.89.0-slim-bookworm AS rust-builder

RUN --mount=type=cache,target=/var/cache/apt \
  apt-get update \
  && apt-get install -y --no-install-recommends \
      build-essential \
      clang \
      cmake \
      git \
      lld \
      pkg-config \
      libssl-dev \
      protobuf-compiler \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY source/ ./

# Set build environment variables
# - Set the C/C++ compiler to clang
ENV CC=clang CXX=clang++
# - Set the Rust flags to use lld as the linker
ENV RUSTFLAGS="-C link-arg=-fuse-ld=lld"

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    cargo build --bin dipper-service --release && \
    cp target/release/dipper-service /dipper-service

## Wrapper image for local-network
# Includes configuration script and utilities
FROM debian:bookworm-slim AS wrapper-dev

RUN --mount=type=cache,target=/var/cache/apt \
  apt-get update \
  && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      jq \
      libssl3 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

# Install the dipper-service binary
COPY --from=rust-builder /dipper-service /usr/local/bin/dipper-service

# Add local-network configuration script
ADD run.sh /opt/run.sh

ENTRYPOINT ["bash", "-c", "/opt/run.sh"]
