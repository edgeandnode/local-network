FROM debian:bookworm-slim
ARG BLOCK_ORACLE_COMMIT

# Install dependencies
RUN apt-get update \
  && apt-get install -y curl git jq libssl-dev pkg-config build-essential \
  && rm -rf /var/lib/apt/lists/*

# Install latest Node.js 20 LTS from Nodesource
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
  apt-get install -y nodejs && \
  npm install --global corepack yarn

# Install Foundry
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
  /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/

# Install Rust toolchain
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal

# Install yq
RUN curl -sL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/bin/yq && \
  chmod +x /usr/bin/yq

# Clone and build Block Oracle
WORKDIR /opt

# TODO: replace the commit checkout with --branch once horizon changes are merged to main
RUN git clone https://github.com/graphprotocol/block-oracle && \
  cd block-oracle && git checkout ${BLOCK_ORACLE_COMMIT} && . ~/.bashrc && cargo build -p block-oracle && \
  cp target/debug/block-oracle . && rm -rf target

# Install dependencies for the subgraph
RUN cd /opt/block-oracle/packages/subgraph && yarn

# Clone and setup contracts repository
RUN git clone https://github.com/graphprotocol/contracts && \
  cd /opt/contracts && git checkout bdc66135e7700e9a4dcd6a4beac585337fdb9c21 && \
  cd /opt/contracts/packages/data-edge && corepack enable && pnpm install

# Copy run script
COPY ./run.sh /opt/run.sh

# Run the script on container start
ENTRYPOINT ["bash", "-cl", "/opt/run.sh"]