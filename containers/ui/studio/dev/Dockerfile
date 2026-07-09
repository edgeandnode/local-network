FROM node:22.14-slim
RUN apt-get -qy update && apt-get -qy install --no-install-recommends \
      ca-certificates curl git openssl unzip \
    && rm -rf /var/lib/apt/lists/*
RUN BUN_INSTALL=/root/.bun curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"
WORKDIR /app
