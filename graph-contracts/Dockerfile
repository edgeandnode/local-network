FROM node:23.11-bookworm-slim
RUN apt-get update \
    && apt-get install -y curl git jq nodejs npm \
    && rm -rf /var/lib/apt/lists/*
RUN npm install -g corepack \
    && corepack enable \
    && corepack prepare yarn@4.0.2 --activate \
    && corepack prepare pnpm@9.0.6 --activate
  

# Install Foundry
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
  /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/

WORKDIR /opt

RUN git clone https://github.com/graphprotocol/contracts --branch 'horizon' && \
    cd contracts && git checkout 8e7f89a89731bb01a3a929e2003422829d9f4a9a && \
    pnpm install --ignore-scripts && pnpm build

RUN git clone https://github.com/graphprotocol/graph-network-subgraph --branch 'juanmardefago/horizon-stage-1-signed' && \
  cd graph-network-subgraph && git checkout c5c3040df9e2b913822efb6a475cabc7b536c97d && \
  pnpm install && pnpm add -D ts-node

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh

