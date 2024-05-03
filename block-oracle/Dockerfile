FROM debian:bookworm-slim
RUN apt-get update \
  && apt-get install -y curl git jq libssl-dev nodejs npm pkg-config \
  && rm -rf /var/lib/apt/lists/*
RUN npm install --global yarn
RUN curl -L https://foundry.paradigm.xyz | bash && /root/.foundry/bin/foundryup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
RUN curl https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -L -o /usr/bin/yq && \
  chmod +x /usr/bin/yq

WORKDIR /opt
RUN git clone https://github.com/graphprotocol/block-oracle --branch 'main' && \
  cd block-oracle && . ~/.bashrc && cargo build -p block-oracle && \
  cp target/debug/block-oracle . && rm -rf target
RUN cd /opt/block-oracle/packages/contracts && yarn && \
  cd ../subgraph && yarn
COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
