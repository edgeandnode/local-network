FROM rust:1.70.0-slim-bullseye
RUN apt-get update && \
    apt-get install -y curl git libpq-dev libssl-dev pkg-config protobuf-compiler jq && \
    rm -rf /var/lib/apt/lists/*


RUN git clone https://github.com/semiotic-ai/timeline-aggregation-protocol /opt/build/semiotic-ai/timeline-aggregation-protocol --branch 'main'
RUN --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/root/.cargo/registry \
    cd /opt/build/semiotic-ai/timeline-aggregation-protocol/ && \
    cargo build -p tap_aggregator

COPY ./.env /opt/
COPY ./tap-aggregator/ /opt/tap-aggregator/
WORKDIR /opt
CMD sh tap-aggregator/run.sh
