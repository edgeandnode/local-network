## Local-network wrapper for dipper-service
ARG DIPPER_VERSION
FROM ghcr.io/edgeandnode/dipper-service:${DIPPER_VERSION}

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      jq \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

ADD run.sh /opt/run.sh

ENTRYPOINT ["bash", "-c", "/opt/run.sh"]
