FROM debian:bookworm-slim
RUN apt-get update \
  && apt-get install -y curl git jq nodejs npm \
  && rm -rf /var/lib/apt/lists/*
RUN npm install --global yarn

# Install Foundry
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
  /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/

  RUN curl -sL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/bin/yq && \
  chmod +x /usr/bin/yq

WORKDIR /opt
RUN git clone https://github.com/semiotic-ai/timeline-aggregation-protocol-contracts --branch 'main' && \
  cd timeline-aggregation-protocol-contracts && yarn && forge build
RUN git clone https://github.com/semiotic-ai/timeline-aggregation-protocol-subgraph --branch 'main' --recursive && \
  cd timeline-aggregation-protocol-subgraph && yarn

COPY ./run.sh /opt/run.sh
ENTRYPOINT sh -cl /opt/run.sh
