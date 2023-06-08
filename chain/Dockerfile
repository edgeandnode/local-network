FROM node:16-bullseye
RUN apt-get update && \
    apt-get install -y jq && \
    rm -rf /var/lib/apt/lists/*
RUN wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq && \
    chmod +x /usr/bin/yq

WORKDIR /opt/
RUN git clone https://github.com/graphprotocol/contracts build/graphprotocol/contracts --branch 'v3.0.0'
RUN cd build/graphprotocol/contracts && \
    yarn && yarn build

COPY ./chain/run.sh /opt/
CMD sh run.sh
