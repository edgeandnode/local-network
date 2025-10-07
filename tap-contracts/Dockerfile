FROM debian:bookworm-slim
ARG TAP_CONTRACTS_COMMIT
ARG TAP_SUBGRAPH_COMMIT

RUN apt-get update \
  && apt-get install -y curl git jq \
  && rm -rf /var/lib/apt/lists/*

# Install Node.js 20.x from NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y nodejs

RUN npm install --global yarn

# Install Foundry
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
  /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/

RUN curl -sL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/bin/yq && \
  chmod +x /usr/bin/yq

WORKDIR /opt
RUN git clone https://github.com/semiotic-ai/timeline-aggregation-protocol-contracts && \
  cd timeline-aggregation-protocol-contracts && git checkout ${TAP_CONTRACTS_COMMIT} && \
  yarn && forge build

RUN git clone https://github.com/semiotic-ai/timeline-aggregation-protocol-subgraph --recursive && \
  cd timeline-aggregation-protocol-subgraph && git checkout ${TAP_SUBGRAPH_COMMIT} && yarn

COPY ./run.sh /opt/run.sh
ENTRYPOINT sh -cl /opt/run.sh