# Local Network Testing

## Prerequisites

- On Linux, increase buffer size for go-ipfs QUIC transfers: `sysctl -w net.core.rmem_max=2500000`
  - See https://github.com/lucas-clemente/quic-go/wiki/UDP-Receive-Buffer-Size
- `prettier` & `eslint`

## Initial setup

1. Clone repos: `bash clone-repos.bash`
2. Patch: `bash patch.bash`

## Build

- Clean all build files: `make clean`
- Build all: `make -j`

## Run

`overmind s`
