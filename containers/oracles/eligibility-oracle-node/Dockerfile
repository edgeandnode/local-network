FROM debian:bookworm-slim
ARG ELIGIBILITY_ORACLE_COMMIT

# Build + runtime dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
      build-essential clang cmake lld pkg-config git \
      curl jq unzip ca-certificates \
      libssl-dev librdkafka-dev \
  && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal

# Clone and build eligibility-oracle binary
WORKDIR /opt
ENV CC=clang CXX=clang++
ENV RUSTFLAGS="-C link-arg=-fuse-ld=lld"
RUN git clone https://github.com/edgeandnode/eligibility-oracle-node && \
  cd eligibility-oracle-node && git checkout ${ELIGIBILITY_ORACLE_COMMIT} && \
  . /root/.cargo/env && cargo build --release -p eligibility-oracle && \
  cp target/release/eligibility-oracle /usr/local/bin/eligibility-oracle && \
  cd .. && rm -rf eligibility-oracle-node

# Clean up build-only dependencies
RUN apt-get purge -y build-essential clang cmake lld pkg-config git libssl-dev librdkafka-dev && \
  apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

# Install runtime libraries
RUN apt-get update \
  && apt-get install -y --no-install-recommends libssl3 librdkafka1 \
  && rm -rf /var/lib/apt/lists/*

# rpk CLI for Redpanda topic management
RUN curl -sLO https://github.com/redpanda-data/redpanda/releases/latest/download/rpk-linux-amd64.zip \
  && unzip rpk-linux-amd64.zip -d /usr/local/bin/ \
  && rm rpk-linux-amd64.zip

COPY --chmod=755 ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
