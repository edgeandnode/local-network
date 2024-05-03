FROM debian:bookworm-slim
RUN apt-get update \
  && apt-get install -y curl git jq nodejs npm \
  && rm -rf /var/lib/apt/lists/*
RUN npm install --global corepack yarn \
  && corepack enable && corepack install -g yarn@4.0.2

WORKDIR /opt
RUN git clone https://github.com/graphprotocol/contracts --branch '@graphprotocol/contracts@6.2.1' && \
  cd contracts/packages/contracts && yarn && yarn compile
RUN git clone https://github.com/graphprotocol/graph-network-subgraph --branch 'v1.1.0' && \
  cd graph-network-subgraph && yarn
COPY ./run.sh /opt/run.sh
ENTRYPOINT sh -cl /opt/run.sh
