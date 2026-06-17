# IISA scoring cronjob — clones from git for non-dev deployments.
# Dev overlay mounts local source instead (see compose/dev/dips.yaml).

FROM python:3.11-slim AS builder

WORKDIR /app

ARG IISA_COMMIT=main

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc git protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Clone cronjob source at specified commit
RUN git clone https://github.com/edgeandnode/subgraph-dips-indexer-selection.git /tmp/iisa \
    && cd /tmp/iisa && git checkout ${IISA_COMMIT} \
    && cp cronjobs/compute_scores/*.py cronjobs/compute_scores/requirements.txt /app/ \
    && cp -r cronjobs/compute_scores/proto /app/proto \
    && rm -rf /tmp/iisa

RUN protoc -I proto --python_out=. proto/gateway_queries.proto
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Runtime stage
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /install /usr/local
COPY --from=builder /app/*.py .

RUN useradd -m appuser
USER appuser

CMD ["python", "main.py"]
