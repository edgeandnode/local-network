FROM ghcr.io/foundry-rs/foundry:v1.0.0

# Ensure the data directory is writable by the foundry user (uid 1000)
USER root
RUN mkdir -p /data && chown foundry:foundry /data
USER foundry

WORKDIR /opt

COPY --chmod=755 ./run.sh /opt/run.sh
ENTRYPOINT ["bash", "/opt/run.sh"]
