FROM ghcr.io/graphprotocol/indexer-service-rs:sha-ce303e3
RUN apt-get update \
  && apt-get install -y curl jq \
  && rm -rf /var/lib/apt/lists/*

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
