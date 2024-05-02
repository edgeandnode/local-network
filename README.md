# local-network

a local Graph network for debugging & integration tests

## setup

1. install Docker & Docker Compose
2. `docker compose down && docker compose up --build`

## useful commands

- `docker compose up --build -d ${service}`
- `docker logs -f ${service}`
- `docker system prune`
- `source .env`

## chain

- Foundry docs: https://book.getfoundry.sh/

## ipfs

- cat file via curl: `curl -X POST "http://localhost:5001/api/v0/cat?arg=f1220d6b169dcf83bfe0f615baa2d83e9adf77d520b52faf18a759eb7277b6d66fa7f"`
- cat file via CLI: `ipfs --api=/ip4/127.0.0.1/tcp/5001 cat QmagRyTMp4qcRb8fJufk7urNwCQmmUEB9mC6nxHQuKwydb`
- note: if you have a hex digest, a valid CID for it is the hex digits prefixed by `f1220`. For example, `0xd6b169dcf83bfe0f615baa2d83e9adf77d520b52faf18a759eb7277b6d66fa7f` -> `f1220d6b169dcf83bfe0f615baa2d83e9adf77d520b52faf18a759eb7277b6d66fa7f`

## postgres

- `psql -h localhost -U postgres`
