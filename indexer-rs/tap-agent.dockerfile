FROM rust:1.76.0-slim-bullseye
RUN apt-get update && \
    apt-get install -y curl git libpq-dev libssl-dev pkg-config protobuf-compiler jq && \
    rm -rf /var/lib/apt/lists/*

RUN cargo install --locked sqlx-cli --no-default-features --features native-tls,postgres

RUN git clone https://github.com/graphprotocol/indexer-rs /opt/build/graphprotocol/indexer-rs --branch 'main'
RUN --mount=type=cache,target=/usr/local/cargo/registry/ \
    --mount=type=cache,target=/usr/local/cargo/git/ \
    --mount=type=cache,target=/opt/build/graphprotocol/indexer-rs/target \
    cd /opt/build/graphprotocol/indexer-rs/ && \
    cargo build -p indexer-tap-agent && \
    cp target/debug/indexer-tap-agent ./indexer-tap-agent && \
    chmod +x ./indexer-tap-agent

COPY ./.env /opt/
COPY ./indexer-rs/ /opt/indexer-rs/
WORKDIR /opt
CMD sh indexer-rs/tap-agent.sh
