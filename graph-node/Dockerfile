ARG GRAPH_NODE_VERSION
FROM graphprotocol/graph-node:${GRAPH_NODE_VERSION}
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*
COPY ./run.sh /opt/run.sh
ENTRYPOINT ["sh", "/opt/run.sh"]
