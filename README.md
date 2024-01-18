# Local Net

A local graph network for integration testing

## Requirements

Make sure that your docker machine has at least 12 GB of RAM to build `graph-node`. In terms of disk space required, the entire project can take upwards of 50 GB so make sure your docker machine also has enough space.

Also, make sure to build `graph-node` before running the entire stack, because it requires a lot of resources and probably your computer won't handle building everything at once.

Configure your default machine pubkey in Github to clone private repositories. Make sure your SSH agent has the keys loaded by running: `ssh-add -l`. If not, add them with `ssh-add ~/.ssh/id_rsa`. 
For podman, it looks like it's not possible to use --ssh with MacOS due to [this issue](https://github.com/containers/podman/issues/14074)

## Setup

- Install [Docker](https://docs.docker.com/get-docker/) & [Docker Compose](https://docs.docker.com/compose/)
- On Mac/Windows, comment out the `DOCKER_GATEWAY_HOST` export in `.env`
- `docker compose down && docker compose up --build`
- Run component outside docker compose (e.g. gateway): `docker stop gateway && sh ./gateway/run.sh`

## Notes

- When running a service outside docker compose, make sure to listen on all interfaces (0.0.0.0)
- `node:16-bullseye-slim` images fail to build on MacOS hosts only (wat). So the non-slim image is used.
- You can build them sequentially one by one by using the following command:
```
docker-compose config | yq '.services[] | key' | xargs -I {} docker-compose build {}
```

## Debugging

- Try `docker compose down` or `docker system prune`
- Check controller state with `curl 127.0.0.1:6001/ | jq`
- Follow logs: `docker logs -f --tail 10 ${container_name}`

## FAQ

- Why not use Docker host networking, instead of using `${DOCKER_GATEWAY_HOST}` everywhere?

  Docker host networking isn't supported on Mac/Windows.

## Examples

- load env file: `. ./.env`

### IPFS

- Cat File

  Note that if you have a hex digest, a valid CID for it is the hex digits prefixed by `f1220`. For example, `0xd6b169dcf83bfe0f615baa2d83e9adf77d520b52faf18a759eb7277b6d66fa7f` -> `f1220d6b169dcf83bfe0f615baa2d83e9adf77d520b52faf18a759eb7277b6d66fa7f`

  ```bash
  curl -X POST "http://localhost:5001/api/v0/cat?arg=f1220d6b169dcf83bfe0f615baa2d83e9adf77d520b52faf18a759eb7277b6d66fa7f"
  ```

### Chain

- Enable logging

  ```bash
  curl "localhost:8545" -X POST --data \
    '{"jsonrpc":"2.0","method":"hardhat_setLoggingEnabled","params":[true],"id":1}'
  ```

- Check chain head

  ```bash
  curl "localhost:8545" -X POST --data \
    '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false],"id":1}'
  ```

- Mine block

  ```bash
  cast rpc evm_mine
  ```

### Postgres

- Login

  ```bash
  psql -h localhost -U dev
  ```

### Redpanda

- Consume topic

  ```bash
  docker exec -it redpanda rpk topic consume gateway_client_query_results --brokers="localhost:9092"
  ```

### Graph Contracts

- Check subgraphs

  ```bash
  curl "http://localhost:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network" \
    -H 'content-type: application/json' \
    -d '{"query": "{ subgraphs { id versions { subgraphDeployment { ipfsHash } } } }"}' | \
    jq '.'
  ```

- Check allocations

  ```bash
  curl "http://localhost:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network" \
    -H 'content-type: application/json' \
    -d '{"query": "{ allocations(where:{status:Active}) { id indexer { url } } }"}' | \
    jq '.'
  ```

### Block Oracle (EBO)

- Block Oracle message encoder: https://graphprotocol.github.io/block-oracle/

- Check subgraph status

  ```bash
  curl "http://localhost:${GRAPH_NODE_GRAPHQL}/subgraphs/name/block-oracle" \
    -H 'content-type: application/json' \
    -d '{"query": "{ networks { id latestValidBlockNumber { id } } }"}'
  ```

### Gateway

- Query gateway by deployment

  ```bash
  curl "http://localhost:${GATEWAY}/api/deployments/id/$(curl -s http://localhost:${CONTROLLER}/block_oracle_subgraph)" \
    -H 'content-type: application/json' -H "Authorization: Bearer deadbeefdeadbeefdeadbeefdeadbeef" \
    -d '{"query": "{ _meta { block { number } } }"}'
  ```

### Indexer

- CLI setup

  ```bash
  ./build/graphprotocol/indexer/packages/indexer-cli/bin/graph-indexer \
    indexer connect "http://localhost:${INDEXER_MANAGEMENT}"
  ```

- Check status

  ```bash
  ./build/graphprotocol/indexer/packages/indexer-cli/bin/graph-indexer \
    indexer status --network=hardhat
  ```
