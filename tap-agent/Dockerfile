# TODO: update to use the latest version of tap-agent
FROM ghcr.io/graphprotocol/indexer-tap-agent:v1.9.1
RUN apt-get update \
    && apt-get install -y git jq \
    && rm -rf /var/lib/apt/lists/*

RUN cd /opt && git clone https://github.com/graphprotocol/indexer-rs

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
