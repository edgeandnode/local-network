FROM node:16-bullseye
RUN apt-get update && \
    apt-get install -y jq libssl-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/
RUN mkdir -p -m 0700 ~/.ssh && \
    ssh-keyscan github.com >> ~/.ssh/known_hosts
RUN --mount=type=ssh \
    git clone git@github.com:edgeandnode/subgraph-studio build/edgeandnode/subgraph-studio --branch 'v0.16.13'
RUN cd build/edgeandnode/subgraph-studio && \
    yarn setup

COPY ./.env /opt/
COPY ./studio/ /opt/studio/
