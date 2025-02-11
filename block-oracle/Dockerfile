FROM debian:bookworm-slim

# Install dependencies
RUN apt-get update \
  && apt-get install -y curl git jq libssl-dev pkg-config build-essential \
  && rm -rf /var/lib/apt/lists/*

# Install latest Node.js 20 LTS from Nodesource
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
  apt-get install -y nodejs && \
  npm install --global corepack yarn

# Install Foundry (pinned nightly version)
RUN curl -L https://foundry.paradigm.xyz | bash && \
  /root/.foundry/bin/foundryup --install nightly-0e519ffde8ab5babde7dffa96fca28cfa3608b59

# Install Rust toolchain
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal

# Install yq
RUN curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/bin/yq && \
  chmod +x /usr/bin/yq

# Clone and build Block Oracle
WORKDIR /opt
RUN git clone https://github.com/graphprotocol/block-oracle --branch 'main' && \
  cd block-oracle && . ~/.bashrc && cargo build -p block-oracle && \
  cp target/debug/block-oracle . && rm -rf target

# Install dependencies for the subgraph
RUN cd /opt/block-oracle/packages/subgraph && yarn

# Clone and setup contracts repository
RUN git clone https://github.com/graphprotocol/contracts --branch 'main' && \
  cd /opt/contracts/packages/data-edge && corepack enable && yarn

# Copy run script
COPY ./run.sh /opt/run.sh

# Run the script on container start
ENTRYPOINT ["bash", "-cl", "/opt/run.sh"]
