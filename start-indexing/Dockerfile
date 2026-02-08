FROM node:23.11-bookworm-slim

RUN apt-get update \
  && apt-get install -y curl jq \
  && rm -rf /var/lib/apt/lists/*

# Foundry (cast for GNS publish + evm_mine)
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
  /usr/local/bin/cast /usr/local/bin/

# Indexer CLI
RUN npm install --global @graphprotocol/indexer-cli@~0.23.0

COPY --chmod=755 ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
