FROM node:23.11-bookworm-slim
ARG NETWORK_SUBGRAPH_COMMIT
ARG TAP_SUBGRAPH_COMMIT
ARG BLOCK_ORACLE_COMMIT

RUN apt-get update \
  && apt-get install -y curl git jq \
  && rm -rf /var/lib/apt/lists/*

# Package managers via corepack (non-strict: repos mix pnpm/yarn packageManager fields)
ENV COREPACK_ENABLE_STRICT=0
RUN corepack enable \
  && corepack prepare pnpm@9.0.6 --activate \
  && corepack prepare yarn@1.22.22 --activate

# yq
RUN curl -sL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/bin/yq && \
  chmod +x /usr/bin/yq

WORKDIR /opt

# 1. Network subgraph
RUN git clone https://github.com/graphprotocol/graph-network-subgraph && \
  cd graph-network-subgraph && git checkout ${NETWORK_SUBGRAPH_COMMIT} && \
  pnpm install && pnpm add -D ts-node

# 2. TAP subgraph
RUN git clone https://github.com/semiotic-ai/timeline-aggregation-protocol-subgraph --recursive && \
  cd timeline-aggregation-protocol-subgraph && git checkout ${TAP_SUBGRAPH_COMMIT} && yarn

# 3. Block oracle subgraph
RUN git clone https://github.com/graphprotocol/block-oracle && \
  cd block-oracle && git checkout ${BLOCK_ORACLE_COMMIT} && \
  cd packages/subgraph && yarn

COPY --chmod=755 ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
