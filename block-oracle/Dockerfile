FROM node:18-bullseye
RUN apt-get update && \
    apt-get install -y ca-certificates curl gettext-base git gnupg jq libssl-dev npm pkg-config wget yarn && \
    rm -rf /var/lib/apt/lists/*
RUN curl -L https://foundry.paradigm.xyz | bash && . /root/.bashrc && foundryup
ENV PATH="$PATH:/root/.foundry/bin"
RUN wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && \
    chmod +x /usr/bin/yq
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /opt/
RUN git clone https://github.com/graphprotocol/block-oracle build/graphprotocol/block-oracle --branch 'main'
# Install dependencies
# Compile contracts
# Compile subgraph

RUN --mount=type=cache,target=/usr/local/share/.cache/yarn/v6,sharing=locked \
    cd /opt/build/graphprotocol/block-oracle/packages/contracts && \
    yarn && \
    npx hardhat compile && \
    cd ../subgraph && \
    yarn && \
    yarn prepare && \
    yarn prep:local && \
    yarn codegen && \
    npx graph build --network hardhat

ENV RUST_BACKTRACE='1'
ENV RUST_LOG=debug

RUN --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/opt/build/graphprotocol/block-oracle/target \
    cd /opt/build/graphprotocol/block-oracle && \
    cargo build -p block-oracle && \
    cp target/debug/block-oracle ./block-oracle



COPY ./.env /opt/
COPY ./block-oracle/ /opt/block-oracle/
CMD sh ./block-oracle/run.sh
