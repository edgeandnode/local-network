ARG TAP_AGGREGATOR_VERSION
FROM ghcr.io/semiotic-ai/tap_aggregator:${TAP_AGGREGATOR_VERSION}
RUN apt-get update \
    && apt-get install -y jq \
    && rm -rf /var/lib/apt/lists/*

COPY ./run.sh /opt/run.sh
ENTRYPOINT ["sh", "/opt/run.sh"]
