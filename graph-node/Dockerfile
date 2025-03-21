FROM graphprotocol/graph-node:v0.37.0
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*
COPY ./run.sh /opt/run.sh
ENTRYPOINT sh -cl /opt/run.sh
