FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y clang cmake curl git jq libsasl2-dev libssl-dev pkg-config protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal

WORKDIR /opt
RUN git clone https://github.com/edgeandnode/gateway --branch 'tmigone/semiotic-main' && \
    cd gateway && git checkout 72646e75d4dccf78759c3e7aea8482c448a91a8b && \
    . /root/.cargo/env && cargo build -p graph-gateway && \
    cp target/debug/graph-gateway /usr/local/bin/graph-gateway && cd .. && rm -rf gateway
COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
