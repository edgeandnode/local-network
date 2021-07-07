# Local Indexer

## Prerequisites

- [overmind](https://github.com/DarthSim/overmind) is required for managing
  subprocesses and tear down everything if one of the processes exits.

## Run

1. Run a local Postgres database server at port 5432.
2. Edit `graph-node.sh`, `indexer-agent.sh` and `indexer-service.sh` to configure things.
3. Open a terminal in this directory and run the following to spin up
   `indexer-agent` and `indexer-service`:

   ```sh
   overmind s
   ```

## Logs

The logs from the different processes are written to the following files:

- `/tmp/graph-node.log`
- `/tmp/indexer-agent.log`
- `/tmp/indexer-service.log`

The indexer agent and service logs can best be searched with a command like the
one below. The logs are raw JSON and each log message is exactly one line. For
this reason it's best to grep for something before pretty printing the logs.

```sh
tail -n 10000 -f /tmp/indexer-agent.log | grep "something" | pino-pretty | less
```
