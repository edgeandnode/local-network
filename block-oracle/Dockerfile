FROM debian:bookworm-slim
RUN apt-get update \
  && apt-get install -y curl git jq libssl-dev nodejs npm pkg-config \
  && rm -rf /var/lib/apt/lists/*
RUN npm install --global corepack yarn
RUN curl -L https://foundry.paradigm.xyz | bash && \
  /root/.foundry/bin/foundryup --install nightly-cafc2606a2187a42b236df4aa65f4e8cdfcea970
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
RUN curl https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -L -o /usr/bin/yq && \
  chmod +x /usr/bin/yq

WORKDIR /opt
RUN git clone https://github.com/graphprotocol/block-oracle --branch 'main' && \
  cd block-oracle && . ~/.bashrc && cargo build -p block-oracle && \
  cp target/debug/block-oracle . && rm -rf target
RUN cd /opt/block-oracle/packages/subgraph && yarn
RUN git clone https://github.com/graphprotocol/contracts --branch 'main' && \
  cd /opt/contracts/packages/data-edge && corepack enable && corepack install -g yarn@4.0.2 && yarn
COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
