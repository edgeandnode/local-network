FROM --platform=linux/amd64 node:16-bullseye
RUN apt-get update && \
    apt-get install -y jq libssl-dev && \
    rm -rf /var/lib/apt/lists/*
RUN curl https://sh.rustup.rs -sSf | bash -s -- -y --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /opt/
# can't use release version until this is included:
# https://github.com/graphprotocol/indexer/commit/d37964a1d1d14c5778faff605ffdc1eb0
RUN git clone https://github.com/graphprotocol/indexer build/graphprotocol/indexer --branch 'main'
RUN cd build/graphprotocol/indexer && yarn --frozen-lockfile --non-interactive

COPY ./.env /opt/
COPY ./indexer/ /opt/indexer/
