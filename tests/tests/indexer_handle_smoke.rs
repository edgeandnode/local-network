//! Smoke test for the per-test indexer fixture.
//!
//! Brings up a fresh per-test indexer stack via `IndexerHandle::new`, verifies
//! the agent's management API responds with the injected identity, then drops
//! the handle (compose project teardown via `down -v`).

use anyhow::Result;
use local_network_tests::indexer::IndexerHandle;

#[tokio::test]
async fn indexer_handle_brings_up_and_registers() -> Result<()> {
    let indexer = IndexerHandle::new("smoke").await?;

    let query = r#"{ indexerRegistration(protocolNetwork: "eip155:1337") {
        address registered url
    } }"#;
    let client = reqwest::Client::new();
    let resp: serde_json::Value = client
        .post(&indexer.management_url)
        .header("content-type", "application/json")
        .json(&serde_json::json!({ "query": query }))
        .send()
        .await?
        .json()
        .await?;

    let registrations = resp["data"]["indexerRegistration"]
        .as_array()
        .expect("indexerRegistration should be an array");
    assert!(
        !registrations.is_empty(),
        "agent should report a registration: {resp}",
    );
    let reg = &registrations[0];
    assert_eq!(
        reg["address"].as_str().map(str::to_lowercase),
        Some(indexer.address.to_lowercase()),
        "agent address should match injected TEST_INDEXER_ADDRESS",
    );

    Ok(())
}
