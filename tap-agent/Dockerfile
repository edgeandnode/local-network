########################################################################
# Build stage
FROM rust:1.86-bookworm AS build

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    protobuf-compiler libsasl2-dev git \
    && rm -rf /var/lib/apt/lists/*

# Clone the indexer-rs repo and checkout horizon branch
RUN git clone https://github.com/graphprotocol/indexer-rs.git . && \
    git checkout suchapalaver/test/horizon

# Force SQLx to use the offline mode to statically check the database queries against
# the prepared files in the `.sqlx` directory.
ENV SQLX_OFFLINE=true

# Build the tap-agent binary
RUN cargo build --release --bin indexer-tap-agent

########################################################################
# Runtime stage
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssl ca-certificates protobuf-compiler libsasl2-2 git jq \
    && rm -rf /var/lib/apt/lists/*

# Copy the built binary from build stage
COPY --from=build /build/target/release/indexer-tap-agent /usr/local/bin/indexer-tap-agent

# Clone indexer-rs for any config files that might be needed at runtime
RUN cd /opt && git clone https://github.com/graphprotocol/indexer-rs.git && \
    cd indexer-rs && git checkout suchapalaver/test/horizon

# Copy the run script
COPY ./run.sh /opt/run.sh

ENTRYPOINT bash -cl /opt/run.sh
