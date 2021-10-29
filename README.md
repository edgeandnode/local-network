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

## Useful commands

- Get API keys:
  ```bash
  psql -h localhost -U postgres -d local_network_subgraph_studio -c 'SELECT * FROM "ApiKeys";'
  ```

- Query indexer status:
  ```bash
  curl localhost:6700/api/${API_KEY}/deployments/id/Qmei3s21mJy6WYy3nTmNFgHKuXmFJCkDtvTR7CeNVPiYiR \
    -H 'Content-Type: application/json' \
    -d '{"query": "{ _meta { block { hash number } } }"}'
  ```

- Query indexer directly:
  ```bash
  curl localhost:8000/subgraphs/id/Qmei3s21mJy6WYy3nTmNFgHKuXmFJCkDtvTR7CeNVPiYiR \
    -H 'Content-Type: application/json' \
    -d '{"query": "{ allocations{ id } }"}'
  ```

- Load env file in Bash:
  ```bash
  set -o allexport; source .overmind.env; set +o allexport
  ```

- Run gateway comparison benchmark
  ```bash
  cd bench && yarn
  # Benchmark TypeScript gateway
  ts-node bench.ts \
    gateway-ts \
    "http://${HOST}:${PORT}/api/${API_KEY}/deployments/id/Qmei3s21mJy6WYy3nTmNFgHKuXmFJCkDtvTR7CeNVPiYiR" \
    |& tee bench-ts.csv
  # Benchmark Rust gateway
  ts-node bench.ts \
    gateway-rs \
    "http://${HOST}:${PORT}/api/${API_KEY}/deployments/id/Qmei3s21mJy6WYy3nTmNFgHKuXmFJCkDtvTR7CeNVPiYiR" \
    |& tee bench-rs.csv
  # Show plots
  python plot.py bench-{ts,rs}.csv
  ```
