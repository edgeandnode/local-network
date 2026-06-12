# Adds the local-network deploy script on top of the contracts workspace
# image. Set CONTRACTS_VERSION=local to consume a `just build-image` from
# the contracts repo when working against an unmerged branch.
ARG CONTRACTS_VERSION
FROM ghcr.io/graphprotocol/contracts:${CONTRACTS_VERSION}

COPY --chmod=755 ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
