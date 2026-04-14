ARG TAP_ESCROW_MANAGER_VERSION
FROM ghcr.io/edgeandnode/tap-escrow-manager:${TAP_ESCROW_MANAGER_VERSION}

# Tools needed by run.sh (config generation, contract_addr helper, topic creation)
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl jq unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# rpk CLI for Redpanda topic management
RUN curl -sLO https://github.com/redpanda-data/redpanda/releases/latest/download/rpk-linux-amd64.zip \
    && unzip rpk-linux-amd64.zip -d /usr/local/bin/ \
    && rm rpk-linux-amd64.zip

# Upstream puts the binary at /opt/tap-escrow-manager; expose on PATH so run.sh can
# invoke `tap-escrow-manager` directly.
RUN ln -sf /opt/tap-escrow-manager /usr/local/bin/tap-escrow-manager

COPY ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
