//! Network State Observation Tests (BaselineTestPlan Cycles 1, 3.1, 6)
//!
//! Verifies the running local network matches BaselineTestPlan expectations.
//! All tests are read-only — they observe state without modifying it.
//!
//! Mapping to BaselineTestPlan:
//!   - `indexer_registered` → Cycle 1.1 (stake) + 1.2 (url, geoHash)
//!   - `provision_exists` → Cycle 1.3 + 3.1 (provision with tokensProvisioned)
//!   - `active_allocations` → Cycle 4.1 (active allocations exist)
//!   - `gateway_serves_queries` → Cycle 5.1 (gateway reachable)
//!   - `indexer_health_metrics` → Cycle 6.1 (all expected fields populated)
//!   - `epoch_progressing` → Cycle 6.2 (currentEpoch > 0)
//!   - `reo_contract_state` → IndexerTestGuide prerequisites

use anyhow::Result;
use local_network_tests::TestNetwork;

fn net() -> Result<TestNetwork> {
    TestNetwork::from_default_env()
}

/// BaselineTestPlan 1.1 + 1.2: Indexer registered with stake, URL, and geoHash.
///
/// Verification query matches the BaselineTestPlan 1.1/1.2 queries.
#[tokio::test]
async fn indexer_registered() -> Result<()> {
    let net = net()?;
    let indexer = net.query_indexer(&net.indexer_address).await?;

    assert!(
        !indexer.is_null(),
        "Indexer entity should exist in subgraph"
    );

    let staked = indexer["stakedTokens"].as_str().unwrap_or("0");
    assert!(
        staked != "0",
        "stakedTokens should be non-zero, got {staked}"
    );

    let url = indexer["url"].as_str().unwrap_or("");
    assert!(!url.is_empty(), "url should be set");

    let geo = indexer["geoHash"].as_str().unwrap_or("");
    assert!(!geo.is_empty(), "geoHash should be set");

    Ok(())
}

/// BaselineTestPlan 1.3 + 3.1: Provision exists with non-zero tokensProvisioned.
///
/// Verifies the indexer-agent automatically created a SubgraphService provision.
/// Emulates `graph indexer provisions get` (Cycle 3.1).
#[tokio::test]
async fn provision_exists() -> Result<()> {
    let net = net()?;
    let provisions = net.query_provisions(&net.indexer_address).await?;
    let provisions = provisions
        .as_array()
        .expect("provisions should be an array");

    assert!(
        !provisions.is_empty(),
        "At least one provision should exist for the indexer"
    );

    let first = &provisions[0];
    let tokens = first["tokensProvisioned"].as_str().unwrap_or("0");
    assert!(
        tokens != "0",
        "tokensProvisioned should be non-zero, got {tokens}"
    );

    Ok(())
}

/// BaselineTestPlan 4.1: Active allocations exist with non-zero allocatedTokens.
#[tokio::test]
async fn active_allocations() -> Result<()> {
    let net = net()?;
    let allocs = net.query_active_allocations(&net.indexer_address).await?;
    let allocs = allocs.as_array().expect("allocations should be an array");

    assert!(
        !allocs.is_empty(),
        "At least one active allocation should exist"
    );

    for alloc in allocs {
        let tokens = alloc["allocatedTokens"].as_str().unwrap_or("0");
        assert!(
            tokens != "0",
            "allocatedTokens should be non-zero for allocation {}",
            alloc["id"]
        );
    }

    Ok(())
}

/// BaselineTestPlan 5.1: Gateway serves queries (reachability check).
///
/// Full query success rate is tested in `allocation_lifecycle::gateway_query_serving`.
/// This test confirms the gateway is reachable and returns valid JSON.
#[tokio::test]
async fn gateway_serves_queries() -> Result<()> {
    let net = net()?;
    net.mine_blocks(5).await?;

    let resp = net
        .gateway_query(r#"{ _meta { block { number } } }"#)
        .await?;
    assert!(
        resp.status().is_success(),
        "Gateway should return 200, got {}",
        resp.status()
    );

    let body: serde_json::Value = resp.json().await?;
    assert!(body.is_object(), "Gateway should return JSON, got {body}");

    Ok(())
}

/// BaselineTestPlan 6.1: Indexer health — all expected fields populated.
///
/// Queries the same fields as BaselineTestPlan 6.1 and verifies the indexer
/// has active allocations visible and accumulated metrics present.
#[tokio::test]
async fn indexer_health_metrics() -> Result<()> {
    let net = net()?;
    let indexer = net.query_indexer(&net.indexer_address).await?;

    assert!(!indexer.is_null(), "Indexer entity should exist");

    // All expected fields should be populated (not null)
    for field in [
        "stakedTokens",
        "allocatedTokens",
        "availableStake",
        "url",
        "geoHash",
    ] {
        assert!(
            !indexer[field].is_null(),
            "Indexer field '{field}' should be populated"
        );
    }

    // Active allocations should be visible
    let allocs = indexer["allocations"]
        .as_array()
        .expect("allocations should be an array");
    assert!(
        !allocs.is_empty(),
        "Active allocations should be visible in indexer entity"
    );

    // Log accumulated metrics (may be zero on a fresh network)
    let rewards = indexer["rewardsEarned"].as_str().unwrap_or("n/a");
    let fees = indexer["queryFeesCollected"].as_str().unwrap_or("n/a");
    let delegated = indexer["delegatedTokens"].as_str().unwrap_or("n/a");
    eprintln!("=== BaselineTestPlan 6.1: Indexer Health ===");
    eprintln!("  rewardsEarned: {rewards}");
    eprintln!("  queryFeesCollected: {fees}");
    eprintln!("  delegatedTokens: {delegated}");
    eprintln!("  activeAllocations: {}", allocs.len());

    Ok(())
}

/// BaselineTestPlan 6.2: Epoch progressing (currentEpoch > 0).
#[tokio::test]
async fn epoch_progressing() -> Result<()> {
    let net = net()?;
    let network = net.query_network().await?;

    let epoch = network["currentEpoch"]
        .as_u64()
        .or_else(|| {
            network["currentEpoch"]
                .as_str()
                .and_then(|s| s.parse().ok())
        })
        .unwrap_or(0);
    assert!(epoch > 0, "currentEpoch should be > 0, got {epoch}");

    Ok(())
}

/// IndexerTestGuide prerequisites: REO contract state.
///
/// Verifies eligibility validation is enabled and the oracle has been updated.
/// These are prerequisites for IndexerTestGuide Sets 2-4.
#[tokio::test]
async fn reo_contract_state() -> Result<()> {
    let net = net()?;
    if net.contracts.reo.is_none() {
        eprintln!("REO not deployed, skipping");
        return Ok(());
    }

    let validation = net.reo_validation_enabled()?;
    assert!(validation, "Eligibility validation should be enabled");

    let last_update = net.reo_last_oracle_update()?;
    assert!(
        last_update > 0,
        "Last oracle update time should be > 0, got {last_update}"
    );

    let eligible = net.reo_is_eligible(&net.indexer_address)?;
    eprintln!("  isEligible({}) = {eligible}", net.indexer_address);

    Ok(())
}
