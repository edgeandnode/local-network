# v0.36.0 has a janky IPFS client
FROM graphprotocol/graph-node:9fdfdca
RUN apt-get update && apt-get install -y \
  curl \
  && rm -rf /var/lib/apt/lists/*
COPY ./run.sh /opt/run.sh
ENTRYPOINT sh -cl /opt/run.sh
