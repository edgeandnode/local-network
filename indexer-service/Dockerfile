FROM rust:1.86-bookworm AS rust-builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        git \
        pkg-config \
        protobuf-compiler \
        libssl-dev \
        libsasl2-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Clone the indexer-rs repo and checkout horizon-migration-fix-support branch
RUN git clone https://github.com/graphprotocol/indexer-rs.git . && \
    git checkout suchapalaver/horizon-migration-fix-support

# Force SQLx to use the offline mode to statically check the database queries against
# the prepared files in the `.sqlx` directory.
ENV SQLX_OFFLINE=true

RUN cargo build --release --bin indexer-service-rs

FROM debian:bookworm-slim AS wrapper-dev

RUN apt-get update \
    && apt-get install -y curl jq \
    && rm -rf /var/lib/apt/lists/*

COPY --from=rust-builder /build/target/release/indexer-service-rs /usr/local/bin/indexer-service-rs

COPY ./run.sh /opt/run.sh

ENTRYPOINT bash -cl /opt/run.sh

## Wrapper image (using same binary from horizon-migration-fix-support branch)
FROM debian:bookworm-slim AS wrapper

RUN apt-get update \
    && apt-get install -y curl jq openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=rust-builder /build/target/release/indexer-service-rs /usr/local/bin/indexer-service-rs

COPY ./run.sh /opt/run.sh

ENTRYPOINT bash -cl /opt/run.sh