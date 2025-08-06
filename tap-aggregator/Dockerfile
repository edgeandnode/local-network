FROM ghcr.io/semiotic-ai/tap_aggregator:sha-44626ee
RUN apt-get update \
    && apt-get install -y jq \
    && rm -rf /var/lib/apt/lists/*

COPY ./run.sh /opt/run.sh
ENTRYPOINT sh -cl /opt/run.sh
