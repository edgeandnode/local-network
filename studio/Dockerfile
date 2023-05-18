FROM node:16-bullseye
RUN apt-get update && \
    apt-get install -y jq libssl-dev && \
    rm -rf /var/lib/apt/lists/*

ARG GH_TOKEN
RUN git config --global url."https://${GH_TOKEN}:@github.com/".insteadOf "https://github.com/"

WORKDIR /opt/
RUN git clone https://github.com/edgeandnode/subgraph-studio build/edgeandnode/subgraph-studio --branch 'v0.16.13'
RUN cd build/edgeandnode/subgraph-studio && \
    yarn setup

COPY ./.env /opt/
COPY ./studio/ /opt/studio/
