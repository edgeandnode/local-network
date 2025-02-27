FROM node:20.11-bookworm-slim
RUN apt-get update \
    && apt-get install -y curl git jq nodejs npm \
    && rm -rf /var/lib/apt/lists/*
RUN npm install --global corepack yarn \
    && corepack enable && corepack install -g yarn@4.0.2

RUN curl -L https://foundry.paradigm.xyz | bash && \
  /root/.foundry/bin/foundryup --install nightly-0e519ffde8ab5babde7dffa96fca28cfa3608b59
ENV PATH="$PATH:/root/.foundry/bin"

WORKDIR /opt

RUN git clone https://github.com/graphprotocol/contracts --branch 'tmigone/horizon-post-oz-audit2' && \
  cd contracts && yarn && yarn build

# # RUN git clone https://github.com/graphprotocol/graph-network-subgraph --branch 'v1.1.0' && \
# #   cd graph-network-subgraph && yarn

COPY ./run.sh /opt/run.sh

ENTRYPOINT bash -cl /opt/run.sh

