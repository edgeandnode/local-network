# latest release doesn't support address book override
FROM ghcr.io/graphprotocol/indexer-agent:sha-ed0b25a
RUN apt-get update \
  && apt-get install -y jq \
  && rm -rf /var/lib/apt/lists/*
RUN curl -L https://foundry.paradigm.xyz | bash && /root/.foundry/bin/foundryup

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
