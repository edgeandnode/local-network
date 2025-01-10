FROM debian:bookworm-slim
RUN apt-get update \
  && apt-get install -y clang cmake curl git jq libsasl2-dev libssl-dev pkg-config zip \
  && rm -rf /var/lib/apt/lists/*
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
RUN curl -L https://foundry.paradigm.xyz | bash && \
  /root/.foundry/bin/foundryup --install nightly-cafc2606a2187a42b236df4aa65f4e8cdfcea970
RUN curl -LO https://github.com/redpanda-data/redpanda/releases/latest/download/rpk-linux-amd64.zip && unzip rpk-linux-amd64.zip -d /usr/local/bin/

WORKDIR /opt
RUN git clone https://github.com/edgeandnode/tap-escrow-manager --branch 'main' && \
  cd tap-escrow-manager && . /root/.cargo/env && cargo build -p tap-escrow-manager && \
  cp target/debug/tap-escrow-manager /usr/local/bin/tap-escrow-manager && cd .. && rm -rf tap-escrow-manager

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
