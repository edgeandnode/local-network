FROM ghcr.io/graphprotocol/indexer-agent:v0.21.9
RUN apt-get update \
  && apt-get install -y jq \
  && rm -rf /var/lib/apt/lists/*
RUN curl -L https://foundry.paradigm.xyz | bash && \
  /root/.foundry/bin/foundryup --install nightly-cafc2606a2187a42b236df4aa65f4e8cdfcea970
RUN npm install -g ts-node nodemon prettier eslint

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
