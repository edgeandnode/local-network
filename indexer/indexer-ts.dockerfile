FROM node:18-bookworm
RUN apt-get update && \
    apt-get install -y jq libssl-dev build-essential && \
    rm -rf /var/lib/apt/lists/*
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /opt/

RUN git clone https://github.com/graphprotocol/indexer build/graphprotocol/indexer --branch 'gusinacio/collect-tap-ravs'

RUN --mount=type=cache,target=/usr/local/share/.cache/yarn/v6,sharing=locked \
    cd build/graphprotocol/indexer && yarn --frozen-lockfile --non-interactive

COPY ./.env /opt/
COPY ./indexer/ /opt/indexer/
