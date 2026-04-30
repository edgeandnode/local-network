FROM node:22-bookworm-slim

RUN apt-get update \
  && apt-get install -y curl git jq python3 make g++ libudev-dev libusb-1.0-0-dev \
  && rm -rf /var/lib/apt/lists/*

# Corepack provides pnpm — the repo's packageManager field selects the version
RUN corepack enable

# Foundry (forge for compilation, cast for run.sh)
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
  /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/

WORKDIR /opt

# Clone and build the contracts repo
# Same CONTRACTS_COMMIT as graph-contracts-horizon.
ARG CONTRACTS_COMMIT
RUN git clone https://github.com/graphprotocol/contracts && \
  cd contracts && git checkout ${CONTRACTS_COMMIT} && \
  pnpm install --frozen-lockfile && pnpm build

COPY --chmod=755 ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
