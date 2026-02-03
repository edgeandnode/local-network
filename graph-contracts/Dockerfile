FROM node:23.11-bookworm-slim
ARG CONTRACTS_COMMIT
ARG NETWORK_SUBGRAPH_COMMIT

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

RUN git clone https://github.com/graphprotocol/contracts && \
  cd contracts && git checkout ${CONTRACTS_COMMIT} && \
  pnpm install --ignore-scripts && pnpm build

RUN git clone https://github.com/graphprotocol/graph-network-subgraph && \
  cd graph-network-subgraph && git checkout ${NETWORK_SUBGRAPH_COMMIT} && \
  pnpm install && pnpm add -D ts-node

COPY ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
