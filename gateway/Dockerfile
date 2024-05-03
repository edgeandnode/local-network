FROM debian:bookworm-slim
RUN apt-get update \
  && apt-get install -y clang cmake curl gettext-base git jq libsasl2-dev libssl-dev pkg-config \
  && rm -rf /var/lib/apt/lists/*
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal

WORKDIR /opt
RUN git clone https://github.com/edgeandnode/gateway --branch 'main' && \
  cd gateway && . /root/.cargo/env && cargo build -p graph-gateway
COPY ./run.sh /opt/run.sh
COPY ./config.json /opt/config.json
ENTRYPOINT bash -cl /opt/run.sh
