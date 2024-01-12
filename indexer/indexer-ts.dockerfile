FROM node:16-bullseye
RUN apt-get update && \
    apt-get install -y jq libssl-dev && \
    rm -rf /var/lib/apt/lists/*
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"


WORKDIR /opt/
RUN git clone https://github.com/graphprotocol/common-ts build/graphprotocol/common-ts --branch 'theodus/local-net'
RUN cd build/graphprotocol/common-ts && yarn
RUN git clone https://github.com/graphprotocol/indexer build/graphprotocol/indexer --branch 'ford/agora-upgrade'
RUN cd build/graphprotocol/indexer && yarn --frozen-lockfile --non-interactive

COPY ./.env /opt/
COPY ./indexer/ /opt/indexer/
