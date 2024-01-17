FROM node:16-bullseye
RUN apt-get update && \
    apt-get install -y jq && \
    rm -rf /var/lib/apt/lists/*
RUN curl -L https://foundry.paradigm.xyz | bash && . /root/.bashrc && foundryup
ENV PATH="$PATH:/root/.foundry/bin"
RUN wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && chmod +x /usr/bin/yq

WORKDIR /opt/
RUN git clone https://github.com/semiotic-ai/timeline-aggregation-protocol-contracts build/semiotic-ai/timeline-aggregation-protocol-contracts --branch main
RUN cd build/semiotic-ai/timeline-aggregation-protocol-contracts && yarn && forge build

COPY ./.env /opt/
COPY ./tap-contracts/ /opt/tap-contracts/
CMD sh ./tap-contracts/contracts.sh
