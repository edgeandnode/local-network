# Build from source using horizon branch
FROM node:20-slim AS builder

# Install dependencies needed for building
RUN apt-get update \
    && apt-get install -y git python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

# Clone the indexer repository and checkout horizon branch
RUN git clone https://github.com/graphprotocol/indexer.git /indexer \
    && cd /indexer \
    && git checkout horizon

# Build the indexer-agent
WORKDIR /indexer
RUN yarn install --frozen-lockfile \
    && yarn build

# Runtime stage
FROM node:20-slim

RUN apt-get update \
    && apt-get install -y jq \
    && rm -rf /var/lib/apt/lists/*

# Install Foundry
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
    /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/

RUN npm install -g tsx nodemon prettier eslint

# Copy built indexer-agent from builder stage
COPY --from=builder /indexer/packages/indexer-agent /opt/indexer/packages/indexer-agent
COPY --from=builder /indexer/packages/indexer-common /opt/indexer/packages/indexer-common

WORKDIR /opt/indexer/packages/indexer-agent

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
