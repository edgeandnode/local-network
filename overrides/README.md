# Development Environments build on local-network

## graph-node 

Graph node development works with the local network by mounting the source directory defined at `GRAPH_NODE_SOURCE_ROOT`, and builds using the `rust:latest` official rust docker image.

Build artifacts are mounted at /tmp/graph-node-docker-build (host and container), and `CARGO_HOME` is set to `/tmp/graph-node-cargo-home` to reduce build times.

### Debugging
Local debugging of the service can be enabled, allowing source-level debug with gdb or an IDE. With the env var `WAIT_FOR_DEBUG` is not an empty string, we will execute the `graph-node` binary in a gdb server exposed on :2345.

### Example vscode launch.json
```json 
{
    // Use IntelliSense to learn about possible attributes.
    // Hover to view descriptions of existing attributes.
    // For more information, visit: https://go.microsoft.com/fwlink/?linkid=830387
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Attach to Remote GDB Server",
            "type": "cppdbg",
            "request": "launch",
            "program": "${workspaceFolder}/target/debug/graph-node", // Path to the binary on the local machine
            "miDebuggerServerAddress": "localhost:2345", // Address of the remote GDB server
            "miDebuggerPath": "/usr/bin/gdb", // Path to GDB on the local machine
            "cwd": "${workspaceFolder}", // Current working directory
            "environment": [],
            "externalConsole": false,
            "MIMode": "gdb",
            "setupCommands": [
                {
                    "description": "Enable pretty-printing for gdb",
                    "text": "-enable-pretty-printing",
                    "ignoreFailures": true
                }
            ],
            "logging": {
                "engineLogging": true
            },
            "sourceFileMap": {
                "/app": "${workspaceFolder}" // Maps the /app directory in the container to the local workspace
            }
        }
    ]
}
```

If either the build or execution of the graph-node fail then we fall into a trap and pause the container using `tail -f /dev/null`.

## indexer-agent, indexer-service (ts) (Hotload Dev Environment)

This is a draft/POC of a hotload dev environment for the indexer agent. It's intended to provide a quick and easy way to iterate on the indexer codebase without having to rebuild the docker image and restart the stack.

## Usage Examples

To bring the whole stack up using the override, simply specify the override file when running `docker compose up`:

```
INDEXER_AGENT_SOURCE_ROOT=<your indexer source root>  \
docker-compose down && \
docker compose up -f docker-compose.yaml -f overrides/indexer-agent-dev/indexer-agent-dev.yaml -d
```

To update the container (when making changes to the entrypoint or Dockerfile), you'll need to rebuild the image and restart the container:

```
# in the root of this checkout, with the local-network up and running, replace the indexer-agent with a hotload dev environment
INDEXER_AGENT_SOURCE_ROOT=<your indexer source root>  \
docker compose \
-f docker-compose.yaml \
-f overrides/indexer-agent-dev/indexer-agent-dev.yaml \
up -d --no-deps indexer-agent
```

This will apply the overrides to the indexer-agent service to the docker-compose stack running and start it.
