FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y clang cmake curl git jq libsasl2-dev libssl-dev pkg-config protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal

WORKDIR /opt
RUN git clone https://github.com/suchapalaver/gateway && \
    cd gateway && git checkout 20fc916f27af3b05851a613c9118c2e8b7dc792a && \
    . /root/.cargo/env && cargo build -p graph-gateway && \
    cp target/debug/graph-gateway /usr/local/bin/graph-gateway && cd .. && rm -rf gateway
COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
