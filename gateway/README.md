# Local Gateway

## Prerequisites

- [overmind](https://github.com/DarthSim/overmind) is required for managing
  subprocesses and tear down everything if one of the processes exits.

- [cloud_sql_proxy](https://cloud.google.com/sql/docs/mysql/sql-proxy) is
  required for connecting to the studio database.

## Testnet vs. Mainnet

## Run

1. Run a local Postgres database server at port 5432.
2. Edit `gateway.sh` and `gateway-agent.sh` to configure things.
3. Open a terminal in this directory and run the following to spin up
   `cloud_sql_proxy`, `gateway` and `gateway-agent`:

```sh
overmind s
```
