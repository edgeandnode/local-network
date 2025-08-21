FROM ghcr.io/graphprotocol/indexer-tap-agent:v1.10.3
RUN apt-get update \
    && apt-get install -y git jq \
    && rm -rf /var/lib/apt/lists/*

RUN cd /opt && git clone https://github.com/graphprotocol/indexer-rs && \
    cd indexer-rs && git checkout a4e9028f7b3dc34ea79fc1b524d3dcdc0017a67c

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
