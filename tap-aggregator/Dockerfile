FROM rust:1.86-bookworm AS build

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    libsasl2-dev \
    protobuf-compiler \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install just for task automation
RUN cargo install just

# Clone TAP horizon branch for v2/horizon features
RUN echo "Cloning timeline-aggregation-protocol horizon branch..." \
    && git clone --depth 1 --branch 'suchapalaver/feat/v2-endpoints' \
    https://github.com/semiotic-ai/timeline-aggregation-protocol tap

WORKDIR /build/tap

# Show build context information
RUN echo "=== TAP Aggregator V2/Horizon Build ===" \
    && echo "Repository: semiotic-ai/timeline-aggregation-protocol" \
    && echo "Branch: horizon" \
    && echo "Commit: $(git rev-parse HEAD)" \
    && echo "Building for local-network v2 upgrade" \
    && echo "======================================="

# Build with v2 features explicitly enabled
RUN echo "Building TAP Aggregator with v2 features..." && \
    cargo build --release --bin tap_aggregator --features v2

# Verify binary was built
RUN ls -la target/release/tap_aggregator && \
    ./target/release/tap_aggregator --help

########################################################################################

FROM debian:bookworm-slim AS runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libsasl2-dev \
    openssl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Copy binary from build stage
COPY --from=build /build/tap/target/release/tap_aggregator /usr/local/bin/tap_aggregator

# Copy run script
COPY ./run.sh /opt/run.sh
RUN chmod +x /opt/run.sh

# Verify binary works
RUN tap_aggregator --help

ENTRYPOINT ["sh", "-cl", "/opt/run.sh"]
