## Local-network wrapper for indexer-service-rs
ARG INDEXER_SERVICE_RS_VERSION
FROM ghcr.io/graphprotocol/indexer-service-rs:${INDEXER_SERVICE_RS_VERSION}

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl jq \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

COPY ./run.sh /opt/run.sh

ENTRYPOINT ["bash", "/opt/run.sh"]
