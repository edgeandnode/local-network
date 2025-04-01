FROM node:20.11-bookworm-slim
RUN apt-get update \
  && apt-get install -y curl git jq \
  && rm -rf /var/lib/apt/lists/*
RUN npm install --global corepack yarn \
  && corepack enable && corepack install -g yarn@4.0.2

RUN curl -L https://foundry.paradigm.xyz | bash && \
  /root/.foundry/bin/foundryup --install nightly-0e519ffde8ab5babde7dffa96fca28cfa3608b59
ENV PATH="$PATH:/root/.foundry/bin"

WORKDIR /opt

# TODO: fix this after the audit is done
RUN git config --global user.email "you@example.com" && \
    git config --global user.name "Your Name"
RUN git clone https://github.com/graphprotocol/contracts --branch 'tmigone/horizon-post-oz-audit2' && \
    cd contracts && \
    git cherry-pick 07aeb21313b7c99c1efaa8d802eaefafb3a8dad3 && \
    git cherry-pick e68d12dbbd981ace41e81a7da1b9e3146848b5e0 && \
    git cherry-pick 6e50e6e90a8cad60cea347aee4b4f7c2f704ca1b && \
    git cherry-pick e8a47dd0e87a554428523caa467c632736e93c73 && \
    yarn && yarn build

RUN git clone https://github.com/graphprotocol/graph-network-subgraph --branch 'juanmardefago/horizon-stage-1' && \
  cd graph-network-subgraph && yarn

COPY ./run.sh /opt/run.sh

ENTRYPOINT bash -cl /opt/run.sh

