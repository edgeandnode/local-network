# check=skip=InvalidDefaultArgInFrom
ARG GRAPH_TALLY_ESCROW_MANAGER_VERSION
FROM ghcr.io/graphprotocol/graph_tally_escrow_manager:${GRAPH_TALLY_ESCROW_MANAGER_VERSION}
RUN apt-get update \
    && apt-get install -y jq \
    && rm -rf /var/lib/apt/lists/*
RUN curl -sLO https://github.com/redpanda-data/redpanda/releases/latest/download/rpk-linux-amd64.zip && unzip rpk-linux-amd64.zip -d /usr/local/bin/

COPY ./run.sh /opt/run.sh
ENTRYPOINT ["sh", "/opt/run.sh"]
