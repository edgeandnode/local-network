# Stage 1: build environment — deps only, reusable as a dev builder
FROM rust:1-slim-bookworm AS build-env
RUN apt-get update \
    && apt-get install -y clang cmake git libsasl2-dev libssl-dev pkg-config protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Stage 2: build the pinned gateway commit
FROM build-env AS build
ARG GATEWAY_COMMIT
WORKDIR /opt
RUN git clone https://github.com/edgeandnode/gateway && \
    cd gateway && git checkout ${GATEWAY_COMMIT} && \
    cargo build -p graph-gateway && \
    cp target/debug/graph-gateway /usr/local/bin/graph-gateway

# Stage 3: minimal runtime
FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y curl jq libsasl2-dev libssl-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /opt
COPY --from=build /usr/local/bin/graph-gateway /usr/local/bin/graph-gateway
COPY ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
