FROM debian:bookworm-slim
ARG BLOCK_ORACLE_COMMIT

# Runtime + build dependencies
RUN apt-get update \
  && apt-get install -y curl git jq libssl-dev pkg-config build-essential \
  && rm -rf /var/lib/apt/lists/*

# Install Rust and build block-oracle binary
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal

WORKDIR /opt
RUN git clone https://github.com/graphprotocol/block-oracle && \
  cd block-oracle && git checkout ${BLOCK_ORACLE_COMMIT} && . ~/.bashrc && cargo build -p block-oracle && \
  cp target/debug/block-oracle . && rm -rf target

# Clean up build-only dependencies
RUN apt-get purge -y pkg-config build-essential git && apt-get autoremove -y && \
  rm -rf /var/lib/apt/lists/*

COPY --chmod=755 ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
