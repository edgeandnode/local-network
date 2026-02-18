## Rust builder
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
      librdkafka-dev \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY source/ ./

ENV CC=clang CXX=clang++
ENV RUSTFLAGS="-C link-arg=-fuse-ld=lld"

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    cargo build --release -p eligibility-oracle && \
    cp target/release/eligibility-oracle /eligibility-oracle

## Wrapper image for local-network
FROM debian:bookworm-slim AS wrapper-dev

RUN --mount=type=cache,target=/var/cache/apt \
  apt-get update \
  && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      jq \
      libssl3 \
      librdkafka1 \
      unzip \
  && rm -rf /var/lib/apt/lists/*

# rpk CLI for Redpanda topic management
RUN curl -sLO https://github.com/redpanda-data/redpanda/releases/latest/download/rpk-linux-amd64.zip \
  && unzip rpk-linux-amd64.zip -d /usr/local/bin/ \
  && rm rpk-linux-amd64.zip

WORKDIR /opt

COPY --from=rust-builder /eligibility-oracle /usr/local/bin/eligibility-oracle

ADD run.sh /opt/run.sh

ENTRYPOINT ["bash", "-c", "/opt/run.sh"]
