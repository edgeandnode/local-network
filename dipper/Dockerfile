FROM debian:bookworm-slim AS builder
RUN apt-get update \
    && apt-get install -y \
    clang \
    cmake \
    curl \
    git \
    jq \
    libsasl2-dev \
    libssl-dev pkg-config \
    protobuf-compiler \
    python3.11 \
    python3.11-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
ADD source /opt/source

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal && \
    cd /opt/source && \
    . /root/.cargo/env && \
    cargo build -p dipper-service

# Run container
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y \
    curl \
    jq \
    libssl-dev pkg-config \
    python3.11-dev \
    && rm -rf /var/lib/apt/lists/*


WORKDIR /opt
ADD run.sh /opt/run.sh

COPY --from=builder /opt/source/target/debug/dipper-service /usr/local/bin/dipper

ENTRYPOINT bash -cl /opt/run.sh
