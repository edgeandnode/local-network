ARG INDEXER_TAP_AGENT_VERSION
FROM ghcr.io/graphprotocol/indexer-tap-agent:${INDEXER_TAP_AGENT_VERSION}
RUN apt-get update \
    && apt-get install -y git jq \
    && rm -rf /var/lib/apt/lists/*

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
