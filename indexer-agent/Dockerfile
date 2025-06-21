########################################################################
# Build image

FROM node:20.11-bookworm-slim as build

ENV NODE_ENV production

RUN apt-get update && apt-get install -y python3 build-essential git curl

WORKDIR /opt/indexer-source

# Clone the indexer repo and checkout horizon branch
RUN git clone https://github.com/graphprotocol/indexer.git . && \
    git checkout horizon

# Install dependencies and build
RUN yarn --frozen-lockfile --non-interactive --production=false

########################################################################
# Runtime image

FROM node:20.11-bookworm-slim

ENV NODE_ENV production
# When simulating large transactions, sometimes indexer-agent runs out of memory.
# This flag seems force node into GC earlier, preventing the crash
# 1536mb is 1.5GB, which is appropriate for an environment with 2GB RAM
# todo: increase this temporarily to 4GB to see if it fixes the crash
ENV NODE_OPTIONS="--max-old-space-size=4096"

RUN apt-get update && apt-get install -y python3 build-essential git curl jq && \
    rm -rf /var/lib/apt/lists/*

# Install Foundry
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
    /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/

WORKDIR /opt/indexer

# Copy root files from build
COPY --from=build /opt/indexer-source/package.json .
COPY --from=build /opt/indexer-source/yarn.lock .
COPY --from=build /opt/indexer-source/tsconfig.json .
COPY --from=build /opt/indexer-source/lerna.json .

# Copy build output
COPY --from=build /opt/indexer-source/packages/indexer-common/package.json /opt/indexer/packages/indexer-common/package.json
COPY --from=build /opt/indexer-source/packages/indexer-common/dist /opt/indexer/packages/indexer-common/dist
COPY --from=build /opt/indexer-source/packages/indexer-agent/package.json /opt/indexer/packages/indexer-agent/package.json
COPY --from=build /opt/indexer-source/packages/indexer-agent/dist /opt/indexer/packages/indexer-agent/dist

# Copy node_modules from build stage to avoid rebuilding
COPY --from=build /opt/indexer-source/node_modules /opt/indexer/node_modules
COPY --from=build /opt/indexer-source/packages/indexer-common/node_modules /opt/indexer/packages/indexer-common/node_modules
COPY --from=build /opt/indexer-source/packages/indexer-agent/node_modules /opt/indexer/packages/indexer-agent/node_modules

RUN npm install -g tsx nodemon prettier eslint

# Copy the run script
COPY ./run.sh /opt/run.sh

ENV ETHEREUM ""

# Run the indexer-agent
WORKDIR /opt/indexer/packages/indexer-agent
ENTRYPOINT bash -cl /opt/run.sh