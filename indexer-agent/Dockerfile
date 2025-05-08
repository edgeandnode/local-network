FROM ghcr.io/graphprotocol/indexer-agent:pr-1094@sha256:f5e20f4d63380ff68c3dfca93ae9acfba6fe9e9ae7aec61049bfadf93963df71
RUN apt-get update \
    && apt-get install -y jq \
    && rm -rf /var/lib/apt/lists/*

# Install Foundry
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
    /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/

RUN npm install -g tsx nodemon prettier eslint

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
