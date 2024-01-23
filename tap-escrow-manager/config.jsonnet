{
    chain_id: 1337,
    escrow_contract: "${escrow}",
    network_subgraph: "http://${DOCKER_GATEWAY_HOST}:${GRAPH_NODE_GRAPHQL}/subgraphs/id/${network_subgraph}",
    escrow_subgraph: "http://${DOCKER_GATEWAY_HOST}:${GRAPH_NODE_GRAPHQL}/subgraphs/id/${escrow_subgraph}",
    kafka: {
        csv_cache: "checkpoint.csv",
        config: {
          "bootstrap.servers": "${DOCKER_GATEWAY_HOST}:${REDPANDA_KAFKA}"
        },
        topic: "gateway_indexer_attempts"
    },
    rpc_url: "http://${DOCKER_GATEWAY_HOST}:${CHAIN_RPC}/",
    secret_key: "${GATEWAY_SENDER}",
}
