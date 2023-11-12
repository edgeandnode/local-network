FROM node:16-bullseye
RUN apt-get update && \
    apt-get install -y jq && \
    rm -rf /var/lib/apt/lists/*
RUN curl -L https://foundry.paradigm.xyz | bash && . /root/.bashrc && foundryup
ENV PATH="$PATH:/root/.foundry/bin"

WORKDIR /opt/
RUN git clone https://github.com/graphprotocol/contracts build/graphprotocol/contracts --branch 'v5.3.0'
RUN cd build/graphprotocol/contracts && yarn && yarn build
RUN git clone https://github.com/graphprotocol/indexer build/graphprotocol/indexer --branch 'v0.20.23'
RUN cd build/graphprotocol/indexer && yarn

COPY ./.env /opt/
COPY ./indexer/ /opt/indexer/
CMD sh ./indexer/allocation.sh
