FROM node:23.11-bookworm-slim
ARG CONTRACTS_COMMIT
ARG TAP_CONTRACTS_COMMIT

RUN apt-get update \
  && apt-get install -y curl git jq \
  && rm -rf /var/lib/apt/lists/*

# Package managers via corepack (non-strict: repos mix pnpm/yarn packageManager fields)
ENV COREPACK_ENABLE_STRICT=0
RUN corepack enable \
  && corepack prepare pnpm@9.0.6 --activate \
  && corepack prepare yarn@1.22.22 --activate

# Foundry
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
  /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/

WORKDIR /opt

# 1. Graph protocol contracts (Horizon)
RUN git clone https://github.com/graphprotocol/contracts && \
  cd contracts && git checkout ${CONTRACTS_COMMIT} && \
  pnpm install --ignore-scripts && pnpm build

# 2. TAP contracts
RUN git clone https://github.com/semiotic-ai/timeline-aggregation-protocol-contracts && \
  cd timeline-aggregation-protocol-contracts && git checkout ${TAP_CONTRACTS_COMMIT} && \
  yarn && forge build

# 3. DataEdge contracts (fixed commit, for block-oracle setup)
RUN git clone https://github.com/graphprotocol/contracts contracts-data-edge && \
  cd contracts-data-edge && git checkout bdc66135e7700e9a4dcd6a4beac585337fdb9c21 && \
  cd packages/data-edge && pnpm install && \
  sed -i "s/localhost/chain/g" hardhat.config.ts && \
  pnpm build

COPY --chmod=755 ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
