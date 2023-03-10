{
    api_key_payment_required: true,
    fisherman: "http://localhost:${FISHERMAN_PORT}",
    gateway_instance_count: 1,
    graph_env_id: "localnet",
    indexer_selection_retry_limit: 2,
    ipfs: "http://localhost:${IPFS_PORT}/api/v0/cat?arg=",
    log_json: false,
    min_indexer_version: "0.0.0",
    network_subgraph: "http://localhost:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/id/${NETWORK_SUBGRAPH_DEPLOYMENT}",
    port_api: ${GATEWAY_PORT},
    port_metrics: ${GATEWAY_METRICS_PORT},
    query_budget_discount: 0.5,
    query_budget_scale: 1.5,
    rate_limit_api_window_secs: 10,
    rate_limit_api_limit: 100,
    rate_limit_ip_window_secs: 10,
    rate_limit_ip_limit: 200,
    # restricted_deployments: "${NETWORK_SUBGRAPH_DEPLOYMENT}=${ACCOUNT_ADDRESS}",
    signer_key: "${MNEMONIC}",
    # special_api_keys:
    studio_auth: "${STUDIO_AUTH}",
    studio_url: "http://localhost:${STUDIO_ADMIN_PORT}/admin/v1",
    # subscriptions_subgraph:

    chains: [
        {
            name: "${ETHEREUM_NETWORK}",
            rpc: "http://localhost:${ETHEREUM_PORT}",
            poll_hz: 3,
        },
    ],

    kafka: {
        "bootstrap.servers": "localhost:${REDPANDA_PORT}",
        // "security.protocol"
        // "sasl.mechanism"
        // "sasl.username"
        // "sasl.password"
        // "ssl.ca.location"
        // "ssl.key.location"
        // "ssl.certificate.location"
    },

    subscriptions_subgraph: "http://localhost:8000/subgraphs/name/edgeandnode-subscriptions",
    subscriptions_contract: "0xd45A464a2412A2f83498d13635698a041b9dBe9b",
    subscriptions_chain_id: 1337,
    subscription_tiers: [
        { payment_rate: "1", query_rate_limit: 1 },
        { payment_rate: "10", query_rate_limit: 10 },
    ],
}