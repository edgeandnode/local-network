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
