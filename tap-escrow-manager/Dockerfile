FROM rust:1.75.0-slim-bullseye
RUN apt-get update && \
    apt-get install -y build-essential cmake curl gettext-base git jq jsonnet librdkafka-dev libsasl2-dev libssl-dev pkg-config unzip && \
    rm -rf /var/lib/apt/lists/*

RUN curl -LO \ 
    https://github.com/redpanda-data/redpanda/releases/latest/download/rpk-linux-amd64.zip && \
    unzip rpk-linux-amd64.zip -d /usr/local/bin/

RUN mkdir -p -m 0700 ~/.ssh && \
    ssh-keyscan github.com >> ~/.ssh/known_hosts
RUN --mount=type=ssh \
    git clone git@github.com:edgeandnode/tap-escrow-manager /opt/build/edgeandnode/tap-escrow-manager --branch 'main'
RUN --mount=type=ssh \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/opt/build/edgeandnode/tap-escrow-manager/target \
    cd /opt/build/edgeandnode/tap-escrow-manager/ && \
    cargo build -p tap-escrow-manager && \
    cp target/debug/tap-escrow-manager ./tap-escrow-manager

RUN curl -L https://foundry.paradigm.xyz | bash && . /root/.bashrc && foundryup
ENV PATH="$PATH:/root/.foundry/bin"

COPY ./.env ./tap-escrow-manager/run.sh /opt/
COPY ./tap-escrow-manager/ /opt/tap-escrow-manager/
WORKDIR /opt/
CMD sh ./tap-escrow-manager/run.sh
