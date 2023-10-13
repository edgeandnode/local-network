{
    api_key_payment_required: true,
    attestations: {
        chain_id: "1337",
        dispute_manager: "${DISPUTE_MANAGER}",
    },
    exchange_rate_provider: "1.0",
    // fisherman: "http://${HOST}:${FISHERMAN_PORT}",
    graph_env_id: "localnet",
    indexer_selection_retry_limit: 2,
    ipfs: "http://${HOST}:${IPFS_RPC}/api/v0/cat?arg=",
    ip_rate_limit: 100,
    log_json: false,
    min_indexer_version: "0.0.0",
    network_subgraph: "http://${HOST}:${GRAPH_NODE_GRAPHQL}/subgraphs/name/graph-network",
    port_api: 6700,
    port_metrics: 7301,
    query_fees_target: 20e-6,
    # restricted_deployments: "${NETWORK_SUBGRAPH_DEPLOYMENT}=${ACCOUNT_ADDRESS}",
    signer_key: "${ACCOUNT0_MNEMONIC}",
    # special_api_keys:
    studio_auth: "${STUDIO_AUTH}",
    studio_url: "http://${HOST}:${STUDIO_ADMIN}/admin/v1",
    # subscriptions_subgraph:

    chains: [
        {
            name: "hardhat",
            rpc: "http://${HOST}:${CHAIN_RPC}",
            poll_hz: 3,
            block_rate_hz: 0.5,
        },
    ],

    kafka: {
        "bootstrap.servers": "${HOST}:${REDPANDA_KAFKA}",
        // "security.protocol"
        // "sasl.mechanism"
        // "sasl.username"
        // "sasl.password"
        // "ssl.ca.location"
        // "ssl.key.location"
        // "ssl.certificate.location"
    },

    // subscriptions_contract: "${SUBSCRIPTIONS_CONTRACT}",
    // subscriptions_chain_id: 1337,
    // subscriptions_owner: "0x90f8bf6a479f320ead074411a4b0e7944ea8c9c1",
    // subscriptions_subgraph: "http://${HOST}:8000/subgraphs/name/edgeandnode-subscriptions",
    // subscriptions_subgraph: "http://${HOST}:${GATEWAY_PORT}/api/deployments/id/${SUBSCRIPTIONS_DEPLOYMENT}",
    // subscriptions_ticket: "oWZzaWduZXJUkPi_akefMg6tB0QRpLDnlE6oycEtTrC6JCzrddbf1iRRG7tiwosxzOq-Oy1gnKNmeThRiHoVSWA_d6wXVEoXN8d6eHk6dtcUG6fLBpyTyLSE8F0IHA",
    // subscription_tiers: [
    //     { payment_rate: "1", queries_per_minute: 10 },
    //     { payment_rate: "10", queries_per_minute: 100 },
    // ],
}
