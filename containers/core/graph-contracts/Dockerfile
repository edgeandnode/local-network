# ============================================================
# Multi-stage build for contract deployment images.
#
# Stages:
#   base         - node 22 + foundry + corepack (mirrors upstream
#                  graphprotocol/contracts CI setup action)
#   contracts-src - `base` + clone and build graphprotocol/contracts
#                  (shared by `contracts` and `issuance`)
#   contracts    - Phase 1 deploy: horizon + subgraph-service
#   issuance     - REO + IA + RAM deploy (GIP-0088)
#   tap          - legacy TAP contracts (separate repo, yarn-based)
#   data-edge    - DataEdge contract from an older contracts snapshot
#
# Each compose service picks its stage via `build.target`.
# ============================================================

# ------------------------------------------------------------
# base: environment shared by every contract deployer.
# Mirrors graphprotocol/contracts' own CI setup:
# .github/actions/setup/action.yml at the pinned commit.
# ------------------------------------------------------------
FROM node:22-bookworm-slim AS base

# libudev-dev / libusb-1.0-0-dev are native deps pulled in by
# hardhat-secure-accounts / ledger toolchain. Upstream CI installs
# these before `pnpm install --frozen-lockfile`.
RUN apt-get update \
  && apt-get install -y curl git jq python3 make g++ libudev-dev libusb-1.0-0-dev \
  && rm -rf /var/lib/apt/lists/*

# Corepack resolves pnpm per-directory from each project's packageManager
# field (pnpm 10.x for the current contracts commit, pnpm 9.0.6 for the
# older DataEdge snapshot — downloaded on demand).
# Strict mode off because TAP contracts (yarn-based) has no packageManager field.
ENV COREPACK_ENABLE_STRICT=0
RUN corepack enable

# Foundry (forge for compile, cast for runtime tx sends in run.sh)
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
  /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/

WORKDIR /opt

# ------------------------------------------------------------
# contracts-src: clone and build graphprotocol/contracts once.
# Shared by `contracts` (Phase 1) and `issuance` (GIP-0088) —
# both deploys live in the same pnpm workspace.
# ------------------------------------------------------------
FROM base AS contracts-src
ARG CONTRACTS_COMMIT
RUN git clone https://github.com/graphprotocol/contracts && \
  cd contracts && git checkout ${CONTRACTS_COMMIT} && \
  pnpm install --frozen-lockfile && pnpm build

# ------------------------------------------------------------
# contracts: Phase 1 — horizon + subgraph-service deploy.
# ------------------------------------------------------------
FROM contracts-src AS contracts
COPY --chmod=755 ./contracts.run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]

# ------------------------------------------------------------
# issuance: GIP-0088 deploy (REO + IA + RAM + activation goals).
# Runs after `contracts` completes; reads horizon addresses from
# the shared config volume.
# ------------------------------------------------------------
FROM contracts-src AS issuance
COPY --chmod=755 ./issuance.run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]

# ------------------------------------------------------------
# tap: legacy TAP contracts (semiotic-ai/timeline-aggregation-protocol-contracts).
# Separate repo, yarn + forge toolchain. Shares only the `base` stage.
# Runs after `contracts` (reads horizon addresses from shared config volume).
# ------------------------------------------------------------
FROM base AS tap
ARG TAP_CONTRACTS_COMMIT
RUN corepack prepare yarn@1.22.22 --activate && \
  git clone https://github.com/semiotic-ai/timeline-aggregation-protocol-contracts && \
  cd timeline-aggregation-protocol-contracts && git checkout ${TAP_CONTRACTS_COMMIT} && \
  yarn && forge build
COPY --chmod=755 ./tap.run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]

# ------------------------------------------------------------
# data-edge: DataEdge contract from a pinned older contracts snapshot.
# Independent of CONTRACTS_COMMIT; runs in parallel with `contracts`.
# The older snapshot declares pnpm@9.0.6 in its packageManager field,
# so corepack resolves that version automatically when entering the dir.
# ------------------------------------------------------------
FROM base AS data-edge
RUN git clone https://github.com/graphprotocol/contracts contracts-data-edge && \
  cd contracts-data-edge && \
  git checkout bdc66135e7700e9a4dcd6a4beac585337fdb9c21 && \
  cd packages/data-edge && pnpm install && \
  sed -i "s/localhost/chain/g" hardhat.config.ts && \
  pnpm build
COPY --chmod=755 ./data-edge.run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
