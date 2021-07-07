# Local Gateway

## Prerequisites

- [overmind](https://github.com/DarthSim/overmind) is required for managing
  subprocesses and tear down everything if one of the processes exits.
- [cloud_sql_proxy](https://cloud.google.com/sql/docs/mysql/sql-proxy) is
  required for connecting to the studio database.

## Run

1. Run a local Postgres database server at port 5432.
2. Edit `gateway.sh` and `gateway-agent.sh` to configure things.
3. Open a terminal in this directory and run the following to spin up
   `cloud_sql_proxy`, `gateway` and `gateway-agent`:

   ```sh
   overmind s
   ```

## Logs

The logs from the different processes are written to the following files:

- `/tmp/gateway-agent.log`
- `/tmp/gateway.log`

The logs can best be searched with a command like the one below. The logs are
raw JSON and each log message is exactly one line. For this reason it's best to
grep for something before pretty printing the logs.

```sh
tail -n 10000 -f /tmp/gateway-agent.log | grep "something" | pino-pretty | less
```
