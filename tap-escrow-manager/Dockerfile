FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y clang cmake curl git jq libsasl2-dev libssl-dev pkg-config zip \
    && rm -rf /var/lib/apt/lists/*
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal

# Install Foundry
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
    /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/

RUN curl -sLO https://github.com/redpanda-data/redpanda/releases/latest/download/rpk-linux-amd64.zip && unzip rpk-linux-amd64.zip -d /usr/local/bin/

WORKDIR /opt
RUN git clone https://github.com/edgeandnode/tap-escrow-manager --branch tmigone/horizon && \
    cd tap-escrow-manager && git checkout d79c1f916713c70877641b0c7ac1f148a1ae7d2b && \
    . /root/.cargo/env && cargo build -p tap-escrow-manager && \
    cp target/debug/tap-escrow-manager /usr/local/bin/tap-escrow-manager && cd .. && rm -rf tap-escrow-manager

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
