## Local-network wrapper for indexer-tap-agent
ARG INDEXER_TAP_AGENT_VERSION
FROM ghcr.io/graphprotocol/indexer-tap-agent:${INDEXER_TAP_AGENT_VERSION}

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl jq \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

COPY ./run.sh /opt/run.sh

ENTRYPOINT ["bash", "/opt/run.sh"]
