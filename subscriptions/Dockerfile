FROM node:16-bullseye
RUN apt-get update && \
    apt-get install -y jq && \
    rm -rf /var/lib/apt/lists/*
RUN wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && \
    chmod +x /usr/bin/yq
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /opt/
RUN git clone https://github.com/edgeandnode/subscription-payments build/edgeandnode/subscription-payments --branch 'main'
RUN --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/root/.cargo/registry \
    cd build/edgeandnode/subscription-payments/contract && yarn && yarn build && \
    cd ../subgraph && yarn && yarn build && \
    cd ../cli && cargo build

COPY ./.env /opt/
COPY ./subscriptions/ /opt/subscriptions/
CMD sh ./subscriptions/run.sh
