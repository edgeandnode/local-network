FROM node:16-bullseye
RUN apt-get update && \
    apt-get install -y jq && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/
RUN git clone https://github.com/graphprotocol/contracts build/graphprotocol/contracts --branch 'v3.0.0'
RUN cd build/graphprotocol/contracts && \
    yarn && yarn build
RUN git clone https://github.com/graphprotocol/graph-network-subgraph build/graphprotocol/graph-network-subgraph --branch 'master'
RUN cd build/graphprotocol/graph-network-subgraph && \
    yarn

COPY ./.env /opt/
COPY ./graph-contracts/ /opt/graph-contracts/
CMD sh ./graph-contracts/run.sh
