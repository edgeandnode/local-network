# TODO: update to use the latest version of tap-aggregator
FROM ghcr.io/semiotic-ai/tap_aggregator:sha-d1cbe8f
RUN apt-get update \
    && apt-get install -y jq \
    && rm -rf /var/lib/apt/lists/*

COPY ./run.sh /opt/run.sh
ENTRYPOINT sh -cl /opt/run.sh
