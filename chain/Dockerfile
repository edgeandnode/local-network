FROM ghcr.io/foundry-rs/foundry:nightly-0e519ffde8ab5babde7dffa96fca28cfa3608b59
WORKDIR /opt

COPY --chmod=755 ./run.sh /opt/run.sh
ENTRYPOINT bash -cl /opt/run.sh