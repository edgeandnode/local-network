FROM rust:1.76.0-slim-bullseye
RUN apt-get update && \
    apt-get install -y build-essential cmake curl gettext-base git jq jsonnet librdkafka-dev libsasl2-dev libssl-dev pkg-config && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p -m 0700 ~/.ssh && \
    ssh-keyscan github.com >> ~/.ssh/known_hosts
RUN --mount=type=ssh \
    git clone git@github.com:edgeandnode/graph-gateway /opt/build/edgeandnode/graph-gateway --branch 'main'
RUN --mount=type=ssh \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/opt/build/edgeandnode/graph-gateway/target \
    cargo install cargo-watch && \
    cd /opt/build/edgeandnode/graph-gateway/ && \
    git checkout -b temp a7874e0acd59f29d947d8a9ef157e4179716058d && \
    cargo build -p graph-gateway && \
    cp target/debug/graph-gateway ./gateway

COPY ./.env ./gateway/run.sh /opt/
COPY ./gateway/ /opt/gateway/
WORKDIR /opt/
CMD sh ./gateway/run.sh
