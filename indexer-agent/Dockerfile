FROM ghcr.io/graphprotocol/indexer-agent:pr-1113@sha256:0f8254487511c08b95e2230cd93052fa24e8f48e214af06a31b0988b6b3dadcf
RUN apt-get update \
    && apt-get install -y jq \
    && rm -rf /var/lib/apt/lists/*

# Install Foundry
COPY --from=ghcr.io/foundry-rs/foundry:v1.0.0 \
    /usr/local/bin/forge /usr/local/bin/cast /usr/local/bin/anvil /usr/local/bin/chisel /usr/local/bin/

RUN npm install -g tsx nodemon prettier eslint

COPY ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh
