# Mirrors graphprotocol/contracts CI environment
# (see .github/actions/setup/action.yml in the contracts repo).
FROM node:24-bookworm-slim
ARG CONTRACTS_COMMIT

# libudev-dev / libusb-1.0-0-dev: required by contracts repo's pnpm install
# (native deps of hardhat-secure-accounts / ledger toolchain). Upstream CI
# installs these same packages before `pnpm install --frozen-lockfile`.
RUN apt-get update \
  && apt-get install -y curl git jq python3 make g++ libudev-dev libusb-1.0-0-dev \
  && rm -rf /var/lib/apt/lists/*

# Corepack resolves pnpm per-directory from each project's `packageManager`
# field (pnpm 10.x for the contracts repo — downloaded on demand).
ENV COREPACK_ENABLE_STRICT=1
RUN corepack enable

# Foundry
COPY --from=ghcr.io/foundry-rs/foundry:stable \
  /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/

WORKDIR /opt

# 1. Graph protocol contracts (Horizon)
#    Install/build commands mirror upstream CI (see contracts repo's
#    .github/actions/setup/action.yml and .github/workflows/build-test.yml).
RUN git clone https://github.com/graphprotocol/contracts && \
  cd contracts && git checkout ${CONTRACTS_COMMIT} && \
  pnpm install --frozen-lockfile && pnpm build

# 2. DataEdge contracts (fixed commit, for block-oracle setup)
RUN git clone https://github.com/graphprotocol/contracts contracts-data-edge && \
  cd contracts-data-edge && git checkout bdc66135e7700e9a4dcd6a4beac585337fdb9c21 && \
  cd packages/data-edge && pnpm install && \
  sed -i "s/localhost/chain/g" hardhat.config.ts && \
  pnpm build

COPY --chmod=755 ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
