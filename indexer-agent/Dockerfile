FROM ghcr.io/graphprotocol/indexer-agent:v0.22.0
RUN apt-get update \
  && apt-get install -y jq \
  && rm -rf /var/lib/apt/lists/*
RUN curl -L https://foundry.paradigm.xyz | bash && \
  /root/.foundry/bin/foundryup --install nightly-0e519ffde8ab5babde7dffa96fca28cfa3608b59
RUN npm install -g tsx nodemon prettier eslint

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
