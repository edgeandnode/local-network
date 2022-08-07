# Local Graph Testnet

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Overmind](https://github.com/DarthSim/overmind)
- curl, jq, psql, sh
- JS/TS stuff: yarn, yalc, typescript, ts-node, pino-pretty
- Login to NPM

## Run

`overmind s`

## Useful commands

- Load env file in shell:

  ```sh
  . .overmind.env
  ```

- Get API keys:

  ```sh
  psql -h localhost -U dev -d local_network_subgraph_studio -c 'SELECT * FROM "ApiKeys";'
  ```

  or

  ```sh
  API_KEY=$(curl "http://localhost:${STUDIO_ADMIN_PORT}/admin/v1/gateway-api-keys" \
    -H "Authorization: Bearer $(cat build/studio-admin-auth.txt)" \
    | jq '.api_keys[0].key' -r)
  ```

- Query indexer status:

  ```sh
  curl localhost:6700/api/${API_KEY}/deployments/id/${NETWORK_SUBGRAPH_DEPLOYMENT} \
    -H 'Content-Type: application/json' \
    -d '{"query": "{ _meta { block { number } } }"}'
  ```

- Query using subgraph name:

  ```sh
  curl localhost:6700/api/${API_KEY}/subgraphs/id/${NETWORK_SUBGRAPH_ID_0} \
    -H 'Content-Type: application/json' \
    -d '{"query": "{ _meta { block { number } } }"}'
  ```

- Query indexer directly:

  ```sh
  curl localhost:8000/subgraphs/id/${NETWORK_SUBGRAPH_DEPLOYMENT} \
    -H 'Content-Type: application/json' \
    -d '{"query": "{ allocations { id } }"}'
  ```

- Connect indexer CLI

  ```sh
  ./build/graphprotocol/indexer/packages/indexer-cli/bin/graph-indexer indexer connect http://localhost:18000
  ```

- Consume Kafka topics

  ```sh
  docker exec -it redpanda-1 rpk topic consume gateway_client_query_results --brokers="${REDPANDA_BROKERS}"
  ```

- Query chain

  ```sh
  curl "localhost:${ETHEREUM_PORT}" -X POST --data \
    '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
  ```

- Add API key indexer preferences

  `psql -h localhost -U postgres -d local_network_subgraph_studio`

  ```sh
  INSERT INTO "IndexerPreferences" (name, description, "order") VALUES ('Fastest speed', 'Time between the query and the response from an indexer. If you mark this as important we will optimize for fast indexers.', 1);
  INSERT INTO "IndexerPreferences" (name, description, "order") VALUES ('Lowest price', 'The amount paid per query. If you mark this as important we will optimize for the less expensive indexers.', 2);
  INSERT INTO "IndexerPreferences" (name, description, "order") VALUES ('Data freshness', 'How recent the latest block an indexer has processed for the subgraph you are querying. If you mark this as important we will optimize to find the indexers with the freshest data.', 3);
  INSERT INTO "IndexerPreferences" (name, description, "order") VALUES ('Economic security', 'The amount of GRT an indexer can lose if they respond incorrectly to your query. If you mark this as important we will optimize for indexers with a large stake.', 4);

  INSERT INTO "ApiKeyIndexerPreferences" ("apiKeyId", "indexerPreferenceId", "points", "weight")
  SELECT 1, id, 0, 0.00 FROM "IndexerPreferences";
  ```
