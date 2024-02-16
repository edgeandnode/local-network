FROM rust:1-slim-bullseye
RUN apt-get update && \
    apt-get install -y curl git libpq-dev libssl-dev pkg-config protobuf-compiler && \
    rm -rf /var/lib/apt/lists/*

ENV COMMIT_HASH='b1bf41c'
ENV REPOSITORY='https://github.com/graphprotocol/graph-node'

RUN git clone $REPOSITORY \
    /opt/build/graphprotocol/graph-node &&\
    cd /opt/build/graphprotocol/graph-node  && \
    git checkout $COMMIT_HASH 

RUN --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/opt/build/graphprotocol/graph-node/target \
    cd /opt/build/graphprotocol/graph-node/ && \
    cargo build -p graph-node &&\
    cp target/debug/graph-node ./graph-node

COPY ./.env ./graph-node/run.sh /opt/
WORKDIR /opt/
CMD sh run.sh
