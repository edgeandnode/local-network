########################################################################
# Build stage - builds from source
FROM node:20.11-bookworm-slim AS builder

ENV NODE_ENV production

RUN apt-get update && apt-get install -y python3 build-essential git curl

WORKDIR /opt/indexer

# Copy root files from source submodule
COPY source/package.json .
COPY source/yarn.lock .
COPY source/tsconfig.json .
COPY source/lerna.json .

# Copy shared and package files
COPY source/packages/indexer-common/ ./packages/indexer-common
COPY source/packages/indexer-agent/ ./packages/indexer-agent

# Install dependencies; include dev dependencies for building
RUN yarn --frozen-lockfile --non-interactive --production=false

########################################################################
# Wrapper development image - builds from source
FROM node:20.11-bookworm-slim AS wrapper-dev

ENV NODE_ENV production
# Increase memory for large transactions
ENV NODE_OPTIONS="--max-old-space-size=4096"

RUN apt-get update && apt-get install -y python3 build-essential git curl jq \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/indexer

# Copy root files
COPY source/package.json .
COPY source/yarn.lock .
COPY source/tsconfig.json .
COPY source/lerna.json .

# Copy build output from builder
COPY --from=builder /opt/indexer/packages/indexer-common/package.json /opt/indexer/packages/indexer-common/package.json
COPY --from=builder /opt/indexer/packages/indexer-common/dist /opt/indexer/packages/indexer-common/dist
COPY --from=builder /opt/indexer/packages/indexer-agent/package.json /opt/indexer/packages/indexer-agent/package.json
COPY --from=builder /opt/indexer/packages/indexer-agent/dist /opt/indexer/packages/indexer-agent/dist

# Install production dependencies only
RUN yarn --frozen-lockfile --non-interactive

# Install extra development tools
RUN npm install -g tsx nodemon prettier eslint

# Install Foundry
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
    /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/

# Copy the custom run script
COPY ./run.sh /opt/run.sh

WORKDIR /opt/indexer/packages/indexer-agent
ENTRYPOINT bash -cl /opt/run.sh

########################################################################
# Wrapper image - uses pre-built image
FROM ghcr.io/graphprotocol/indexer-agent:pr-1113@sha256:3c59d1bb151bb25261adb6a93dc22433b9ccec6039802532151277728c892da8 AS wrapper
RUN apt-get update \
    && apt-get install -y jq \
    && rm -rf /var/lib/apt/lists/*

# Install Foundry
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
    /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/

RUN npm install -g tsx nodemon prettier eslint

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
