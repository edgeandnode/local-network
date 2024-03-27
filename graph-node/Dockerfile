FROM rust:1-slim-bullseye
RUN apt-get update && \
    apt-get install -y curl git libpq-dev libssl-dev pkg-config postgresql protobuf-compiler && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/graphprotocol/graph-node /opt/build/graphprotocol/graph-node --branch 'v0.34.1'
RUN --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/root/.cargo/registry \
    cd /opt/build/graphprotocol/graph-node/ && \
    cargo build -p graph-node

COPY . /opt/
WORKDIR /opt/
CMD sh ./run.sh
