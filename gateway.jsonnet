{
    api_key_payment_required: true,
    exchange_rate_provider: "1.0",
    fisherman: "http://localhost:${FISHERMAN_PORT}",
    gateway_instance_count: 1,
    graph_env_id: "localnet",
    indexer_selection_retry_limit: 2,
    ipfs: "http://localhost:${IPFS_PORT}/api/v0/cat?arg=",
    ip_rate_limit: 100,
    log_json: false,
    min_indexer_version: "0.0.0",
    network_subgraph: "http://localhost:${GRAPH_NODE_GRAPHQL_PORT}/subgraphs/id/${NETWORK_SUBGRAPH_DEPLOYMENT}",
    port_api: ${GATEWAY_PORT},
    port_metrics: ${GATEWAY_METRICS_PORT},
    query_budget_discount: 0.5,
    query_budget_scale: 1.5,
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
            block_rate_hz: 0.5,
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

    subscriptions_contract: "${SUBSCRIPTIONS_CONTRACT}",
    subscriptions_chain_id: 1337,
    subscriptions_owner: "0x90f8bf6a479f320ead074411a4b0e7944ea8c9c1",
    // subscriptions_subgraph: "http://localhost:8000/subgraphs/name/edgeandnode-subscriptions",
    subscriptions_subgraph: "http://localhost:${GATEWAY_PORT}/api/deployments/id/${SUBSCRIPTIONS_DEPLOYMENT}",
    subscriptions_ticket: "oWZzaWduZXJUkPi_akefMg6tB0QRpLDnlE6oycEtTrC6JCzrddbf1iRRG7tiwosxzOq-Oy1gnKNmeThRiHoVSWA_d6wXVEoXN8d6eHk6dtcUG6fLBpyTyLSE8F0IHA",
    subscription_tiers: [
        { payment_rate: "1", queries_per_minute: 10 },
        { payment_rate: "10", queries_per_minute: 100 },
    ],
}
