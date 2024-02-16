FROM node:20-bookworm
RUN apt-get update && \
    apt-get install -y ca-certificates curl gettext-base git gnupg jq libssl-dev npm pkg-config wget yarn && \
    rm -rf /var/lib/apt/lists/*
RUN curl -L https://foundry.paradigm.xyz | bash && . /root/.bashrc && foundryup
ENV PATH="$PATH:/root/.foundry/bin"
RUN wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && \
    chmod +x /usr/bin/yq
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /opt/
RUN git clone https://github.com/graphprotocol/graph-network-subgraph build/graphprotocol/graph-network-subgraph --branch 'master'

RUN --mount=type=cache,target=/usr/local/share/.cache/yarn/v6,sharing=locked \
    cd build/graphprotocol/graph-network-subgraph && \
    yarn && \
    yarn add --dev ts-node

COPY ./.env /opt/
COPY ./graph-contracts/ /opt/graph-contracts/
ENTRYPOINT sh ./graph-contracts/subgraph.sh
