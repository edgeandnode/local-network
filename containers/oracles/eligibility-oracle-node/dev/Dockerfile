# Dev image for eligibility-oracle - runtime only (binary mounted from host)
FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
      curl jq unzip ca-certificates \
      libssl3 librdkafka1 \
  && rm -rf /var/lib/apt/lists/*

# rpk CLI for Redpanda topic management
RUN curl -sLO https://github.com/redpanda-data/redpanda/releases/latest/download/rpk-linux-amd64.zip \
  && unzip rpk-linux-amd64.zip -d /usr/local/bin/ \
  && rm rpk-linux-amd64.zip

WORKDIR /opt
# run.sh is mounted via compose override
ENTRYPOINT ["bash", "/opt/run.sh"]
