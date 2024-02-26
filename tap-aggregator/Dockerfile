FROM rust:1.75.0-slim-bullseye
RUN apt-get update && \
    apt-get install -y curl git libpq-dev libssl-dev pkg-config protobuf-compiler jq && \
    rm -rf /var/lib/apt/lists/*


RUN git clone https://github.com/semiotic-ai/timeline-aggregation-protocol /opt/build/semiotic-ai/timeline-aggregation-protocol --branch 'aasseman/tap_core_0_7_0_fix_toolshed_dep'
RUN --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/opt/build/semiotic-ai/timeline-aggregation-protocol/target \
    cd /opt/build/semiotic-ai/timeline-aggregation-protocol/ && \
    cargo build -p tap_aggregator && \
    cp target/debug/tap_aggregator ./tap-aggregator

COPY ./.env /opt/
COPY ./tap-aggregator/ /opt/tap-aggregator/
WORKDIR /opt
CMD sh tap-aggregator/run.sh
