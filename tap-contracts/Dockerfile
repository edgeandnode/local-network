FROM debian:bookworm-slim
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
RUN git clone https://github.com/semiotic-ai/timeline-aggregation-protocol-contracts --branch 'main' && \
  cd timeline-aggregation-protocol-contracts && git checkout e3351e70b3e5d9821bc0aaa90bb2173ca2a77af7 && \
  yarn && forge build
RUN git clone https://github.com/semiotic-ai/timeline-aggregation-protocol-subgraph --branch 'main' --recursive && \
  cd timeline-aggregation-protocol-subgraph && git checkout cf7279f60433bf9a9d897ec2548c13c0607234cc && yarn

COPY ./run.sh /opt/run.sh
ENTRYPOINT sh -cl /opt/run.sh