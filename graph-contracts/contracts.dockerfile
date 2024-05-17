FROM node:16-bullseye
RUN apt-get update && \
    apt-get install -y ca-certificates curl gettext-base git gnupg jq libssl-dev npm pkg-config wget yarn && \
    rm -rf /var/lib/apt/lists/*
RUN curl -L https://foundry.paradigm.xyz | bash && . /root/.bashrc && foundryup
ENV PATH="$PATH:/root/.foundry/bin"
RUN wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && \
    chmod +x /usr/bin/yq

WORKDIR /opt/
RUN git clone https://github.com/graphprotocol/contracts build/graphprotocol/contracts --branch 'v5.3.0'

RUN --mount=type=cache,target=/usr/local/share/.cache/yarn/v6,sharing=locked \
    cd build/graphprotocol/contracts && yarn && yarn build

COPY ./.env /opt/
COPY ./graph-contracts/ /opt/graph-contracts/
CMD sh ./graph-contracts/contracts.sh