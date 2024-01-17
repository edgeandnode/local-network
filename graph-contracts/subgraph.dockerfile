FROM node:20-bookworm
RUN apt-get update && \
    apt-get install -y curl jq yarn && \
    rm -rf /var/lib/apt/lists/*
RUN curl -L https://foundry.paradigm.xyz | bash && . /root/.bashrc && foundryup
ENV PATH="$PATH:/root/.foundry/bin"

WORKDIR /opt/
RUN git clone https://github.com/graphprotocol/graph-network-subgraph build/graphprotocol/graph-network-subgraph --branch 'master'
RUN cd build/graphprotocol/graph-network-subgraph && yarn && yarn add --dev ts-node

COPY ./.env /opt/
COPY ./graph-contracts/ /opt/graph-contracts/
ENTRYPOINT sh ./graph-contracts/subgraph.sh
