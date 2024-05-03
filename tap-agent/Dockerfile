FROM ghcr.io/graphprotocol/indexer-tap-agent:main
RUN apt-get update \
  && apt-get install -y clang curl git jq libssl-dev pkg-config \
  && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
RUN . /root/.cargo/env && cargo install sqlx-cli
RUN cd /opt && git clone https://github.com/graphprotocol/indexer-rs

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
