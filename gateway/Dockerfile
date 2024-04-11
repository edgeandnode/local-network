FROM rust:1-slim-bullseye
RUN apt-get update && \
    apt-get install -y build-essential cmake curl gettext-base git jq jsonnet librdkafka-dev libsasl2-dev libssl-dev pkg-config && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/edgeandnode/graph-gateway /opt/build/edgeandnode/graph-gateway --branch 'main'
RUN --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/root/.cargo/registry \
    cd /opt/build/edgeandnode/graph-gateway/ && \
    cargo build -p graph-gateway

COPY . /opt/
WORKDIR /opt/
CMD sh ./run.sh
