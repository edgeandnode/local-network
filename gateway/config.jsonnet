{
    api_key_payment_required: true,
    attestations: {
        chain_id: "1337",
        dispute_manager: "${DISPUTE_MANAGER}",
    },
    block_oracle_subgraph: "http://${DOCKER_GATEWAY_HOST}:${GRAPH_NODE_GRAPHQL}/subgraphs/name/block-oracle",
    chains: [
        {
            names: ["hardhat"],
            rpc: "http://${DOCKER_GATEWAY_HOST}:${CHAIN_RPC}",
        },
    ],
    exchange_rate_provider: 1.0,
    graph_env_id: "localnet",
    indexer_selection_retry_limit: 2,
    ipfs: "http://${DOCKER_GATEWAY_HOST}:${IPFS_RPC}/api/v0/cat?arg=",
    ip_rate_limit: 100,
    kafka: {
        "bootstrap.servers": "${DOCKER_GATEWAY_HOST}:${REDPANDA_KAFKA}",
    },
    log_json: false,
    min_graph_node_version: "0.33.0",
    min_indexer_version: "0.0.0",
    network_subgraph: "http://${DOCKER_GATEWAY_HOST}:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network",
    port_api: 6700,
    port_metrics: 7301,
    query_fees_target: 20e-6,
    scalar: {
        chain_id: "1337",
        signer: "${GATEWAY_SIGNER}",
        verifier: "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
    },
    studio_auth: "${STUDIO_AUTH}",
    studio_url: "http://${DOCKER_GATEWAY_HOST}:${STUDIO_ADMIN}/admin/v1",
}
