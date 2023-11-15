FROM node:18-bullseye
RUN apt-get update && \
    apt-get install -y ca-certificates curl gettext-base git gnupg jq libssl-dev npm pkg-config wget yarn python3 build-essential && \
    rm -rf /var/lib/apt/lists/*
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"
RUN curl -L https://foundry.paradigm.xyz | bash && . /root/.bashrc && foundryup
ENV PATH="$PATH:/root/.foundry/bin"
RUN wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && \
    chmod +x /usr/bin/yq

WORKDIR /opt/
RUN git clone https://github.com/graphprotocol/block-oracle build/graphprotocol/block-oracle --branch 'main'
RUN --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/root/.cargo/registry \
    cd /opt/build/graphprotocol/block-oracle && \
    cargo build -p block-oracle
RUN cd build/graphprotocol/block-oracle/packages/contracts && yarn && \
    cd ../subgraph && yarn

COPY ./.env /opt/
COPY ./block-oracle/ /opt/block-oracle/
CMD sh ./block-oracle/run.sh
