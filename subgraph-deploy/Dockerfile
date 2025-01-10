FROM debian:bookworm-slim
RUN apt-get update \
  && apt-get install -y curl jq nodejs npm \
  && rm -rf /var/lib/apt/lists/*
RUN npm install --global @graphprotocol/indexer-cli
RUN curl -L https://foundry.paradigm.xyz | bash && /root/.foundry/bin/foundryup --install nightly-cafc2606a2187a42b236df4aa65f4e8cdfcea970

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
