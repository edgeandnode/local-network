FROM ghcr.io/graphprotocol/indexer-agent:pr-1113@sha256:3fa8a1d49c9e9069a08d5d5eacc15526c4392ba35a7db36c43cb42444ab9bde3
RUN apt-get update \
    && apt-get install -y jq \
    && rm -rf /var/lib/apt/lists/*

# Install Foundry
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
    /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/

RUN npm install -g tsx nodemon prettier eslint

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
