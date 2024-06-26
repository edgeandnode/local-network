# Indexer Agent (Hotload Dev Environment)

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
