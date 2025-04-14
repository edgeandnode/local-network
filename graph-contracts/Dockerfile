FROM node:23.11-bookworm-slim
RUN apt-get update \
    && apt-get install -y curl git jq nodejs npm \
    && rm -rf /var/lib/apt/lists/*
RUN npm install --global corepack yarn \
    && corepack enable && corepack install -g yarn@4.0.2 \
    && corepack enable pnpm && corepack use pnpm@9.0.6

# Install Foundry
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
  /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/

WORKDIR /opt

# TODO: fix this after the audit is done
RUN git config --global user.email "you@example.com" && \
    git config --global user.name "Your Name"

# TODO: remove these cherry picks once audit fixes are merged
RUN git clone https://github.com/graphprotocol/contracts --branch 'tmigone/horizon-post-oz-audit2' && \
    cd contracts && \
    git cherry-pick 07aeb21313b7c99c1efaa8d802eaefafb3a8dad3 && \
    git cherry-pick e68d12dbbd981ace41e81a7da1b9e3146848b5e0 && \
    git cherry-pick 6e50e6e90a8cad60cea347aee4b4f7c2f704ca1b && \
    git cherry-pick e8a47dd0e87a554428523caa467c632736e93c73 && \
    pnpm install --ignore-scripts && pnpm build

RUN git clone https://github.com/graphprotocol/graph-network-subgraph --branch 'juanmardefago/horizon-stage-1' && \
  cd graph-network-subgraph && pnpm install && pnpm add -D ts-node

COPY ./run.sh /opt/run.sh
ENTRYPOINT tail -f /dev/null
# ENTRYPOINT bash -cl /opt/run.sh

