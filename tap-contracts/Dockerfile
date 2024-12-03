FROM debian:bookworm-slim
RUN apt-get update \
  && apt-get install -y curl git jq nodejs npm \
  && rm -rf /var/lib/apt/lists/*
RUN npm install --global yarn
RUN curl -L https://foundry.paradigm.xyz | bash && \
  /root/.foundry/bin/foundryup --version nightly-cafc2606a2187a42b236df4aa65f4e8cdfcea970
RUN curl https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -L -o /usr/bin/yq && \
  chmod +x /usr/bin/yq

WORKDIR /opt
RUN git clone https://github.com/semiotic-ai/timeline-aggregation-protocol-contracts --branch 'main' && \
  cd timeline-aggregation-protocol-contracts && yarn && /root/.foundry/bin/forge build
RUN git clone https://github.com/semiotic-ai/timeline-aggregation-protocol-subgraph --branch 'main' --recursive && \
  cd timeline-aggregation-protocol-subgraph && yarn

COPY ./run.sh /opt/run.sh
ENTRYPOINT sh -cl /opt/run.sh
