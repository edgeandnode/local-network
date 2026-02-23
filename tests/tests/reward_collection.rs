//! Reward Collection Tests — Direct Contract Call
//!
//! Tests `SubgraphService.collect(IndexingRewards)` directly via cast.
//! This bypasses the indexer-agent to verify the raw contract behavior:
//!   create allocation → advance epochs → collect() → verify stake increase
//!
//! Not directly mapped to BaselineTestPlan or IndexerTestGuide — those cover
//! the agent-mediated close path (which does collect internally as a multicall).
//! See `allocation_lifecycle::close_allocation_collects_rewards` for that flow.
//!
//! This test provides additional coverage of the underlying contract mechanism.

use anyhow::{Context, Result};
use local_network_tests::TestNetwork;
use serial_test::serial;

fn net() -> Result<TestNetwork> {
    TestNetwork::from_default_env()
}

/// Verify that calling `SubgraphService.collect(IndexingRewards)` mints GRT
/// to the indexer's stake.
///
/// This is the raw contract operation that the indexer-agent invokes as part
/// of its close multicall (collect + stopService).
#[tokio::test]
#[serial]
async fn collect_indexing_rewards_increases_stake() -> Result<()> {
    let net = net()?;

    // Find an active allocation
    let allocs = net.get_allocations().await?;
    let allocs = allocs.as_array().context("expected allocation array")?;
    let active = allocs
        .iter()
        .find(|a| a["closedAtEpoch"].is_null())
        .context("no active allocation found")?;
    let alloc_id = active["id"]
        .as_str()
        .context("allocation missing id")?
        .to_string();
    let deployment = active["subgraphDeployment"]
        .as_str()
        .context("allocation missing deployment")?
        .to_string();

    eprintln!("=== Reward collection test ===");
    eprintln!("  Allocation: {alloc_id}");
    eprintln!("  Deployment: {deployment}");

    // Close and recreate so we have a fresh allocation with known epoch boundaries
    net.advance_epochs(2).await?;
    net.close_allocation(&alloc_id).await?;

    let result = net.create_allocation(&deployment, "0.01").await?;
    let fresh_alloc = result["allocation"]
        .as_str()
        .context("expected allocation ID")?
        .to_string();
    eprintln!("  Fresh allocation: {fresh_alloc}");

    // Advance epochs so rewards accumulate (need > 1 epoch for allocation maturity)
    net.advance_epochs(2).await?;

    // Ensure indexer is eligible (eligibility may have expired during epoch advancement)
    if net.contracts.reo.is_some() {
        net.reo_renew_indexer(&net.indexer_address)?;
        assert!(
            net.reo_is_eligible(&net.indexer_address)?,
            "Indexer must be eligible to collect rewards"
        );
    }

    // Record stake before collect
    let stake_before = net.staked_tokens()?;
    eprintln!("  Stake before collect: {stake_before}");

    // Call collect(IndexingRewards) — this is the key operation
    eprintln!("  Calling collect(IndexingRewards)...");
    net.collect_indexing_rewards(&fresh_alloc)?;

    // Record stake after collect
    let stake_after = net.staked_tokens()?;
    let reward_delta = stake_after.saturating_sub(stake_before);
    let reward_grt = reward_delta as f64 / 1e18;
    eprintln!("  Stake after collect: {stake_after}");
    eprintln!("  Reward delta: {reward_delta} wei ({reward_grt:.2} GRT)");

    assert!(
        stake_after > stake_before,
        "Staked tokens should increase after collect(IndexingRewards). \
         Before: {stake_before}, After: {stake_after}"
    );

    // Restore: close the fresh allocation (if still open) and recreate.
    // The collect() call or the indexer-agent may have auto-closed it.
    net.advance_epochs(2).await?;
    if let Err(e) = net.close_allocation(&fresh_alloc).await {
        eprintln!("  Close skipped (already closed): {e:#}");
    }
    net.create_allocation(&deployment, "0.01").await?;
    eprintln!("  Restored allocation for {deployment}");

    Ok(())
}
