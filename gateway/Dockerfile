FROM rust:1.69.0-slim-bullseye
RUN apt-get update && \
    apt-get install -y build-essential cmake curl gettext-base git jsonnet librdkafka-dev libsasl2-dev libssl-dev pkg-config && \
    rm -rf /var/lib/apt/lists/*

ARG GH_TOKEN
RUN git config --global url."https://${GH_TOKEN}:@github.com/".insteadOf "https://github.com/" && \
    git config --global --add url."https://${GH_TOKEN}:@github.com/".insteadOf "ssh://git@github.com/" && \
    mkdir ~/.cargo && echo "[net]\ngit-fetch-with-cli = true" > ~/.cargo/config.toml

RUN git clone https://github.com/edgeandnode/graph-gateway /opt/build/edgeandnode/graph-gateway --branch 'v13.3.0'
RUN --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/root/.cargo/registry \
    cargo install cargo-watch && \
    cd /opt/build/edgeandnode/graph-gateway/ && \
    cargo build -p graph-gateway

COPY ./.env ./gateway/run.sh /opt/
COPY ./gateway/ /opt/gateway/
WORKDIR /opt/
CMD sh ./gateway/run.sh
