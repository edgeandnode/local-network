FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y curl jq nodejs npm \
    && rm -rf /var/lib/apt/lists/*

# Indexer CLI
RUN npm install --global @graphprotocol/indexer-cli@~0.22.0  # >=0.22.0,<0.23.0

# Foundry
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
  /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/

COPY ./run.sh /opt/run.sh

ENTRYPOINT bash -cl /opt/run.sh
