# latest release doesn't support address book override
FROM ghcr.io/graphprotocol/indexer-service:sha-cbece82
RUN npm install -g ts-node nodemon prettier eslint

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
