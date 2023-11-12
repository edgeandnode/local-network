FROM ghcr.io/foundry-rs/foundry:latest
RUN apk update && \
    apk upgrade && \
    apk add curl nodejs npm jq yarn && \
    rm -rf /var/cache/apk/*

WORKDIR /opt/
RUN git clone https://github.com/graphprotocol/graph-network-subgraph build/graphprotocol/graph-network-subgraph --branch 'master'
RUN cd build/graphprotocol/graph-network-subgraph && yarn

COPY ./.env /opt/
COPY ./graph-contracts/ /opt/graph-contracts/
ENTRYPOINT sh ./graph-contracts/subgraph.sh
