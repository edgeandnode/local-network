ARG GATEWAY_VERSION=v27.6.0
FROM ghcr.io/edgeandnode/graph-gateway:${GATEWAY_VERSION}

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl jq ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# The published image's binary is at /opt/gateway/target/release/graph-gateway (not on
# PATH); run.sh calls `graph-gateway` by name, so put it on PATH.
RUN ln -sf /opt/gateway/target/release/graph-gateway /usr/local/bin/graph-gateway

COPY ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
