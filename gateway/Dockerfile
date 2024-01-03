FROM rust:1.70.0-slim-bullseye
RUN apt-get update && \
    apt-get install -y build-essential cmake curl gettext-base git jq jsonnet librdkafka-dev libsasl2-dev libssl-dev pkg-config && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p -m 0700 ~/.ssh && \
    ssh-keyscan github.com >> ~/.ssh/known_hosts
RUN --mount=type=ssh \
    git clone git@github.com:edgeandnode/graph-gateway /opt/build/edgeandnode/graph-gateway --branch 'v16.1.3'
RUN --mount=type=ssh \
    --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/root/.cargo/registry \
    cargo install cargo-watch && \
    cd /opt/build/edgeandnode/graph-gateway/ && \
    cargo build -p graph-gateway

COPY ./.env ./gateway/run.sh /opt/
COPY ./gateway/ /opt/gateway/
WORKDIR /opt/
CMD sh ./gateway/run.sh
