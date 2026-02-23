//! Provision Management Tests (BaselineTestPlan Cycle 3)
//!
//! Tests adding, thawing, and removing stake from the SubgraphService provision.
//! In production, these operations use `graph indexer provisions` CLI;
//! here we emulate them with direct HorizonStaking contract calls.
//!
//! Mapping to BaselineTestPlan:
//!   - `provision_lifecycle` → Cycle 3.2 (add) + 3.3 (thaw) + 3.4 (deprovision)
//!
//! Note: Cycle 3.1 (view provision) is covered by `network_state::provision_exists`.

use anyhow::Result;
use local_network_tests::TestNetwork;
use serial_test::serial;

fn net() -> Result<TestNetwork> {
    TestNetwork::from_default_env()
}

/// BaselineTestPlan 3.2 + 3.3 + 3.4: Provision add → thaw → deprovision.
///
/// Runs as a single test since each step depends on the previous:
///   1. Add idle stake to provision (emulates `graph indexer provisions add`)
///   2. Thaw from provision (emulates `graph indexer provisions thaw`)
///   3. Advance past thawing period
///   4. Deprovision (emulates `graph indexer provisions remove`)
///   5. Verify tokens return to idle stake
#[tokio::test]
#[serial]
async fn provision_lifecycle() -> Result<()> {
    let net = net()?;
    eprintln!("=== BaselineTestPlan 3.2-3.4: Provision Lifecycle ===");

    let amount = "1000000000000000000000"; // 1000 GRT

    // Add idle stake to work with
    net.stake_tokens(amount)?;
    let idle_before = net.idle_stake()?;
    eprintln!("  Idle stake: {idle_before}");
    assert!(idle_before > 0, "Need idle stake for provision tests");

    // -- 3.2: Add to provision --
    // Emulates: graph indexer provisions add 1000
    eprintln!();
    eprintln!("--- 3.2: Add to provision ---");
    net.provision_add(amount)?;
    let idle_after_add = net.idle_stake()?;
    eprintln!("  Idle stake after provision_add: {idle_after_add}");
    assert!(
        idle_after_add < idle_before,
        "Idle stake should decrease after adding to provision. \
         Before: {idle_before}, After: {idle_after_add}"
    );

    // Verify via subgraph (mine blocks to trigger indexing)
    net.mine_blocks(2).await?;
    tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    let provisions = net.query_provisions(&net.indexer_address).await?;
    let provisioned = provisions
        .as_array()
        .and_then(|p| p.first())
        .and_then(|p| p["tokensProvisioned"].as_str())
        .unwrap_or("0");
    eprintln!("  tokensProvisioned (subgraph): {provisioned}");

    // -- 3.3: Thaw from provision --
    // Emulates: graph indexer provisions thaw 1000
    eprintln!();
    eprintln!("--- 3.3: Thaw from provision ---");
    net.provision_thaw(amount)?;

    // Verify thawing state via subgraph
    net.mine_blocks(2).await?;
    tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    let provisions = net.query_provisions(&net.indexer_address).await?;
    let thawing = provisions
        .as_array()
        .and_then(|p| p.first())
        .and_then(|p| p["tokensThawing"].as_str())
        .unwrap_or("0");
    eprintln!("  tokensThawing (subgraph): {thawing}");
    assert!(
        thawing != "0",
        "tokensThawing should be non-zero after thaw"
    );

    // Get thawing period
    let thawing_period = net.provision_thawing_period().await?;
    eprintln!("  Thawing period: {thawing_period}s");

    // -- 3.4: Deprovision after thawing period --
    // Emulates: graph indexer provisions remove (after waiting for thaw)
    eprintln!();
    eprintln!("--- 3.4: Deprovision ---");
    if thawing_period > 0 {
        eprintln!(
            "  Advancing time by {}s to expire thawing period...",
            thawing_period + 60
        );
        net.advance_time(thawing_period + 60).await?;
    }

    net.provision_deprovision(1)?;
    let idle_final = net.idle_stake()?;
    eprintln!("  Idle stake after deprovision: {idle_final}");

    assert!(
        idle_final > idle_after_add,
        "Idle stake should increase after deprovision. \
         After add: {idle_after_add}, After deprovision: {idle_final}"
    );

    Ok(())
}
