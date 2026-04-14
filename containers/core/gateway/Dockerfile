ARG GATEWAY_VERSION
FROM ghcr.io/edgeandnode/graph-gateway:${GATEWAY_VERSION}

# Tools needed by run.sh (config generation, wait_for_gql)
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl jq ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Upstream ENTRYPOINT is target/release/graph-gateway relative to /opt/gateway;
# expose on PATH so run.sh can invoke `graph-gateway` directly.
RUN ln -sf /opt/gateway/target/release/graph-gateway /usr/local/bin/graph-gateway

WORKDIR /opt
COPY ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
