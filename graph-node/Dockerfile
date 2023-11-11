FROM rust:1.68.0-slim-bullseye
RUN apt-get update && \
    apt-get install -y git libpq-dev libssl-dev pkg-config protobuf-compiler && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/graphprotocol/graph-node /opt/build/graphprotocol/graph-node --branch 'v0.33.0'
RUN --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/root/.cargo/registry \
    cd /opt/build/graphprotocol/graph-node/ && \
    cargo build -p graph-node

COPY ./.env ./graph-node/run.sh /opt/
WORKDIR /opt/
CMD sh run.sh
