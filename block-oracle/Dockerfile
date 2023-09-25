FROM rust:slim-bullseye
RUN apt-get update && \
    apt-get install -y ca-certificates curl gettext-base git gnupg jq libssl-dev pkg-config wget && \
    rm -rf /var/lib/apt/lists/*
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_16.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && apt-get install nodejs && \
    rm -rf /var/lib/apt/lists/*
RUN npm install --global yarn
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
