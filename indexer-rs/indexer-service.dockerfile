FROM rust:1.70.0-slim-bullseye
RUN apt-get update && \
    apt-get install -y curl git libpq-dev libssl-dev pkg-config protobuf-compiler && \
    rm -rf /var/lib/apt/lists/*

RUN cargo install sqlx-cli --no-default-features --features native-tls,postgres

RUN git clone https://github.com/graphprotocol/indexer-rs /opt/build/graphprotocol/indexer-rs --branch 'jannis/subgraph-service'
RUN --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/root/.cargo/registry \
    cd /opt/build/graphprotocol/indexer-rs/ && \
    cargo build -p service

COPY ./.env /opt/
COPY ./indexer-rs/ /opt/indexer-rs/
WORKDIR /opt
CMD sh indexer-rs/indexer-service.sh
