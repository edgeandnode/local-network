FROM debian:bookworm-slim AS builder
ARG BLOCK_ORACLE_COMMIT

RUN apt-get update \
  && apt-get install -y curl git libssl-dev pkg-config build-essential \
  && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /build
RUN git clone https://github.com/graphprotocol/block-oracle && \
  cd block-oracle && git checkout ${BLOCK_ORACLE_COMMIT}

WORKDIR /build/block-oracle
RUN --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/build/block-oracle/target \
    cargo build -p block-oracle && \
    cp target/debug/block-oracle /usr/local/bin/block-oracle

FROM debian:bookworm-slim
RUN apt-get update \
  && apt-get install -y --no-install-recommends curl jq libssl3 ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/block-oracle /usr/local/bin/block-oracle
WORKDIR /opt
COPY --chmod=755 ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
