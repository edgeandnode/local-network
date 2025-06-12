FROM debian:bookworm-slim

# Install system dependencies
# Install system dependencies
RUN apt-get update \
  && apt-get install -y \
    curl \
    git \
    jq \
    libssl-dev \
    pkg-config \
    build-essential \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Install Node.js 20 LTS and pnpm
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y nodejs \
  && corepack enable \
  && corepack prepare pnpm@latest --activate \
  && pnpm config set network-timeout 300000 \
  && pnpm config set fetch-timeout 300000 \
  && pnpm config set registry https://registry.npmjs.org/

# Install Foundry
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
  /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

# Install yq
RUN curl -sL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/bin/yq \
  && chmod +x /usr/bin/yq

WORKDIR /opt

RUN git clone https://github.com/graphprotocol/block-oracle --branch 'main' \
  && git clone https://github.com/graphprotocol/contracts --branch 'main'

RUN cd block-oracle \
  && cargo build -p block-oracle \
  && cp target/debug/block-oracle . \
  && rm -rf target

RUN cd block-oracle/packages/subgraph && yarn install --frozen-lockfile

RUN cd contracts/packages/data-edge \
  && pnpm install --no-frozen-lockfile

COPY ./run.sh /opt/run.sh
RUN chmod +x /opt/run.sh

ENTRYPOINT ["bash", "-cl", "/opt/run.sh"]
