FROM ghcr.io/graphprotocol/indexer-agent:v0.21.4
RUN apt-get update \
  && apt-get install -y jq \
  && rm -rf /var/lib/apt/lists/*
RUN curl -L https://foundry.paradigm.xyz | bash && /root/.foundry/bin/foundryup

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
