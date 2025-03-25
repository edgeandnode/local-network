## Rust builder
# Compile the Rust code and link against the uv-installed libpython
# The libpython3-dev package version must match the final image's python version
FROM rust:slim-bookworm AS rust-builder

RUN --mount=type=cache,sharing=locked,id=apt-lists-debian-bookworm,target=/var/lib/apt/lists \
    --mount=type=cache,sharing=locked,id=apt-cache-debian-bookworm,target=/var/cache/apt \
  rm -f /etc/apt/apt.conf.d/docker-clean \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    clang \
    cmake \
    git \
    lld \
    libsasl2-dev \
    libssl-dev \
    pkg-config \
    protobuf-compiler 

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /opt

# Set build environment variables
#  - Copy packages from the global cache into the site-packages directory
ENV UV_LINK_MODE=copy
# - Set the C/C++ compiler to clang
ENV CC=clang CXX=clang++
# - Set the Rust flags to use lld as the linker
ENV RUSTFLAGS="-C link-arg=-fuse-ld=lld"

COPY source ./
RUN --mount=type=cache,sharing=locked,id=cargo-registry,target=/usr/local/cargo/registry \
    --mount=type=cache,id=dipper-build-cache,target=/opt/target \
    --mount=type=cache,sharing=locked,id=uv,target=/root/.cache/uv \
    uv run cargo build -p dipper-service \
  && cp target/debug/dipper-service /opt/dipper-service

## Python builder
# Package the python code (sdist)
FROM python:3.12.6-slim-bookworm AS python-builder

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /src
COPY source/ ./

RUN uv build --sdist


## Wrapper development image
FROM python:3.12.6-slim-bookworm AS wrapper-dev

# Set uv environment variables
#  - Use the system python
ENV UV_SYSTEM_PYTHON=1
#  - Don't create a virtual environment (.venv) when syncing
ENV UV_PROJECT_ENVIRONMENT=""
#  - Copy packages from the global cache into the site-packages directory
ENV UV_LINK_MODE=copy
#  - Compile Python files to bytecode after installation
ENV UV_COMPILE_BYTECODE=1

WORKDIR /opt

# Install python dependencies
RUN --mount=from=ghcr.io/astral-sh/uv,source=/uv,target=/usr/local/bin/uv \
    --mount=type=cache,sharing=locked,id=uv,target=/root/.cache/uv \
    --mount=type=bind,source=source/pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=source/uv.lock,target=uv.lock \
    uv sync --frozen --no-install-project --no-dev

# Install the iisa python package
RUN --mount=from=ghcr.io/astral-sh/uv,source=/uv,target=/usr/local/bin/uv \
    --mount=from=python-builder,source=/src/dist,target=/src/dist \
    uv pip install --system /src/dist/*.tar.gz

# Install the dipper-service binary
COPY --from=rust-builder /opt/dipper-service /usr/local/bin/dipper-service


RUN --mount=type=cache,sharing=locked,id=apt-lists-debian-bookworm,target=/var/lib/apt/lists \
    --mount=type=cache,sharing=locked,id=apt-cache-debian-bookworm,target=/var/cache/apt \
  rm -f /etc/apt/apt.conf.d/docker-clean \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
      curl \
      jq

ADD run.sh /opt/run.sh

ENTRYPOINT bash -cl /opt/run.sh
