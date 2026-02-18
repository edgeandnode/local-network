## Local-network wrapper for eligibility-oracle-node
#
# Requires a locally-built base image. Build it from the REO repo first:
#   cd /path/to/eligibility-oracle-node && docker build -t eligibility-oracle-node .
ARG REO_IMAGE=eligibility-oracle-node
FROM ${REO_IMAGE}

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
      curl jq unzip \
  && rm -rf /var/lib/apt/lists/*

# rpk CLI for Redpanda topic management
RUN curl -sLO https://github.com/redpanda-data/redpanda/releases/latest/download/rpk-linux-amd64.zip \
  && unzip rpk-linux-amd64.zip -d /usr/local/bin/ \
  && rm rpk-linux-amd64.zip

WORKDIR /opt

ADD run.sh /opt/run.sh

ENTRYPOINT ["bash", "/opt/run.sh"]
