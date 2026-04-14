ARG ELIGIBILITY_ORACLE_NODE_VERSION
FROM ghcr.io/edgeandnode/eligibility-oracle-node:${ELIGIBILITY_ORACLE_NODE_VERSION}

# Upstream image runs as non-root `oracle`; revert for apt-get, run.sh stays as root.
USER root

# Tools needed by run.sh (config generation, block-number polling, rpk install)
RUN apt-get update \
  && apt-get install -y --no-install-recommends curl jq unzip ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# rpk CLI for Redpanda topic management
RUN curl -sLO https://github.com/redpanda-data/redpanda/releases/latest/download/rpk-linux-amd64.zip \
  && unzip rpk-linux-amd64.zip -d /usr/local/bin/ \
  && rm rpk-linux-amd64.zip

WORKDIR /opt
COPY --chmod=755 ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
