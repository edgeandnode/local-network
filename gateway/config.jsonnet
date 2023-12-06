{
    api_key_payment_required: true,
    attestations: {
        chain_id: "1337",
        dispute_manager: "${DISPUTE_MANAGER}",
    },
    chains: [
        {
            name: "hardhat",
            rpc: "http://${DOCKER_GATEWAY_HOST}:${CHAIN_RPC}",
            poll_hz: 3,
            block_rate_hz: 0.5,
        },
    ],
    exchange_rate_provider: "1.0",
    graph_env_id: "localnet",
    indexer_selection_retry_limit: 2,
    ipfs: "http://${DOCKER_GATEWAY_HOST}:${IPFS_RPC}/api/v0/cat?arg=",
    ip_rate_limit: 100,
    kafka: {
        "bootstrap.servers": "redpanda:${REDPANDA_KAFKA}",
    },
    log_json: false,
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

    // subscriptions_contract: "${SUBSCRIPTIONS_CONTRACT}",
    // subscriptions_chain_id: 1337,
    // subscriptions_owner: "0x90f8bf6a479f320ead074411a4b0e7944ea8c9c1",
    // subscriptions_subgraph: "http://${DOCKER_GATEWAY_HOST}:8000/subgraphs/name/edgeandnode-subscriptions",
    // subscriptions_subgraph: "http://${DOCKER_GATEWAY_HOST}:${GATEWAY_PORT}/api/deployments/id/${SUBSCRIPTIONS_DEPLOYMENT}",
    // subscriptions_ticket: "oWZzaWduZXJUkPi_akefMg6tB0QRpLDnlE6oycEtTrC6JCzrddbf1iRRG7tiwosxzOq-Oy1gnKNmeThRiHoVSWA_d6wXVEoXN8d6eHk6dtcUG6fLBpyTyLSE8F0IHA",
    // subscription_tiers: [
    //     { payment_rate: "1", queries_per_minute: 10 },
    //     { payment_rate: "10", queries_per_minute: 100 },
    // ],
}
