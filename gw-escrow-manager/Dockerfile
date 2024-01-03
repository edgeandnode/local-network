FROM rust:1.70.0-slim-bullseye
RUN apt-get update && \
    apt-get install -y build-essential cmake curl gettext-base git jq jsonnet librdkafka-dev libsasl2-dev libssl-dev pkg-config && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p -m 0700 ~/.ssh && \
    ssh-keyscan github.com >> ~/.ssh/known_hosts
RUN --mount=type=ssh \
    git clone git@github.com:edgeandnode/gw-escrow-manager /opt/build/edgeandnode/gw-escrow-manager --branch 'main'
RUN --mount=type=ssh \
    --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/root/.cargo/registry \
    cd /opt/build/edgeandnode/gw-escrow-manager/ && \
    cargo build -p gw-escrow-manager

RUN curl -L https://foundry.paradigm.xyz | bash && . /root/.bashrc && foundryup
ENV PATH="$PATH:/root/.foundry/bin"

COPY ./.env ./gw-escrow-manager/run.sh /opt/
COPY ./gw-escrow-manager/ /opt/gw-escrow-manager/
WORKDIR /opt/
CMD sh ./gw-escrow-manager/run.sh
