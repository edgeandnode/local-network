# check=skip=InvalidDefaultArgInFrom
ARG GRAPH_TALLY_AGGREGATOR_VERSION
FROM ghcr.io/graphprotocol/graph_tally_aggregator:${GRAPH_TALLY_AGGREGATOR_VERSION}
RUN apt-get update \
    && apt-get install -y jq \
    && rm -rf /var/lib/apt/lists/*

COPY ./run.sh /opt/run.sh
ENTRYPOINT ["sh", "/opt/run.sh"]
