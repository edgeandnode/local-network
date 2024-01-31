FROM rust:1.75.0-slim-bullseye

RUN apt-get update && \
    apt-get install -y curl git && \
    rm -rf /var/lib/apt/lists/*

RUN curl -L https://foundry.paradigm.xyz | bash && . /root/.bashrc && foundryup
ENV PATH="$PATH:/root/.foundry/bin"


EXPOSE 8545
ENTRYPOINT ["/bin/bash", "-c"]
