FROM rust:1.76.0-slim-bullseye
RUN apt-get update && \
    apt-get install -y curl git libpq-dev libssl-dev pkg-config protobuf-compiler jq && \
    rm -rf /var/lib/apt/lists/*

RUN cargo install sqlx-cli --no-default-features --features native-tls,postgres

RUN git clone https://github.com/graphprotocol/indexer-rs /opt/build/graphprotocol/indexer-rs --branch 'gusinacio/test-network'
RUN --mount=type=cache,target=/usr/local/cargo/registry/ \
    --mount=type=cache,target=/usr/local/cargo/git/ \
    --mount=type=cache,target=/opt/build/graphprotocol/indexer-rs/target,sharing=locked \
    cd /opt/build/graphprotocol/indexer-rs/ && \
    cargo build -p service && \
    cp target/debug/service ./indexer-service && \
    chmod +x ./indexer-service

COPY ./.env /opt/
COPY ./indexer-rs/ /opt/indexer-rs/
WORKDIR /opt
CMD sh indexer-rs/indexer-service.sh
