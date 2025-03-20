FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y clang cmake curl git jq libsasl2-dev libssl-dev pkg-config zip \
    && rm -rf /var/lib/apt/lists/*
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal

# Install Foundry
COPY --from=ghcr.io/foundry-rs/foundry:nightly-0e519ffde8ab5babde7dffa96fca28cfa3608b59 \
  /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/

RUN curl -sLO https://github.com/redpanda-data/redpanda/releases/latest/download/rpk-linux-amd64.zip && unzip rpk-linux-amd64.zip -d /usr/local/bin/

WORKDIR /opt
RUN git clone https://github.com/edgeandnode/tap-escrow-manager && \
    cd tap-escrow-manager && git checkout 40d889a && . /root/.cargo/env && cargo build -p tap-escrow-manager && \
    cp target/debug/tap-escrow-manager /usr/local/bin/tap-escrow-manager && cd .. && rm -rf tap-escrow-manager

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
