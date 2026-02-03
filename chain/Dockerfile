FROM ghcr.io/foundry-rs/foundry:v1.0.0
WORKDIR /opt

COPY --chmod=755 ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]