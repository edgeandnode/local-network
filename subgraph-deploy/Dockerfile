FROM --platform=linux/amd64 debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y curl jq nodejs npm \
    && rm -rf /var/lib/apt/lists/*

# Indexer CLI
RUN npm install --global @graphprotocol/indexer-cli@~0.22.0  # >=0.22.0,<0.23.0

# Foundry
COPY --from=ghcr.io/foundry-rs/foundry:nightly-0e519ffde8ab5babde7dffa96fca28cfa3608b59 \
  /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/

COPY ./run.sh /opt/run.sh

ENTRYPOINT bash -cl /opt/run.sh
