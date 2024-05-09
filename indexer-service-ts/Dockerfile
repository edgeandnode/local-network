FROM ghcr.io/graphprotocol/indexer-service:v0.21.4
RUN npm install -g ts-node nodemon prettier eslint

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
