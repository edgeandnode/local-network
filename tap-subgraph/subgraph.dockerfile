FROM node:16-bullseye
RUN apt-get update && \
    apt-get install -y jq && \
    rm -rf /var/lib/apt/lists/*
RUN curl -L https://foundry.paradigm.xyz | bash && . /root/.bashrc && foundryup
ENV PATH="$PATH:/root/.foundry/bin"
RUN wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && chmod +x /usr/bin/yq

WORKDIR /opt/
RUN git clone https://github.com/semiotic-ai/timeline-aggregation-protocol-subgraph build/semiotic-ai/timeline-aggregation-protocol-subgraph --branch main
RUN cd build/semiotic-ai/timeline-aggregation-protocol-subgraph && yarn

COPY ./.env /opt/
COPY ./tap-subgraph/ /opt/tap-subgraph/
CMD sh ./tap-subgraph/subgraph.sh
