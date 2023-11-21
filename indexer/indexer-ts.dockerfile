FROM --platform=linux/amd64 node:16-bullseye
RUN apt-get update && \
    apt-get install -y jq libssl-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/
RUN git clone https://github.com/graphprotocol/common-ts build/graphprotocol/common-ts --branch 'theodus/local-net'
RUN cd build/graphprotocol/common-ts && yarn
RUN git clone https://github.com/graphprotocol/indexer build/graphprotocol/indexer --branch 'theodus/local-net'
RUN cd build/graphprotocol/indexer && yarn --frozen-lockfile --non-interactive

COPY ./.env /opt/
COPY ./indexer/ /opt/indexer/
