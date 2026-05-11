//! Reward Collection Tests — Direct Contract Call
//!
//! Tests `SubgraphService.collect(IndexingRewards)` directly via cast on a
//! per-test indexer. Bypasses the agent's close multicall to verify the raw
//! contract behavior: create allocation → advance epochs → collect() → stake
//! delta. The agent-mediated close path is covered by
//! `allocation_lifecycle::close_allocation_collects_rewards`.

use anyhow::{Context, Result};
use local_network_tests::TestNetwork;
use local_network_tests::indexer::IndexerHandle;

fn net() -> Result<TestNetwork> {
    TestNetwork::from_default_env()
}

#[tokio::test]
async fn collect_indexing_rewards_increases_stake() -> Result<()> {
    let net = net()?;
    let indexer = IndexerHandle::new("collect-rewards").await?;

    let deployments = net.query_deployments_with_signal().await?;
    let deployment = deployments
        .as_array()
        .and_then(|d| d.first())
        .and_then(|d| d["ipfsHash"].as_str())
        .context("no signaled deployments")?
        .to_string();

    let create = indexer.create_allocation(&deployment, "0.01").await?;
    let alloc_id = create["allocation"]
        .as_str()
        .context("missing allocation id")?
        .to_string();
    eprintln!("Created allocation {alloc_id}");

    net.advance_epochs(2).await?;

    if net.contracts.reo.is_some() {
        net.reo_renew_indexer(&indexer.address)?;
        assert!(
            net.reo_is_eligible(&indexer.address)?,
            "indexer must be eligible to collect rewards",
        );
    }

    let stake_before = indexer.staked_tokens(&net)?;
    eprintln!("Stake before: {stake_before}");

    indexer.collect_indexing_rewards(&net, &alloc_id)?;

    let stake_after = indexer.staked_tokens(&net)?;
    let delta = stake_after.saturating_sub(stake_before);
    let delta_grt = delta as f64 / 1e18;
    eprintln!("Stake after:  {stake_after} (delta {delta} wei = {delta_grt:.2} GRT)");

    assert!(
        stake_after > stake_before,
        "collect(IndexingRewards) should increase stake. before={stake_before} after={stake_after}",
    );

    Ok(())
}
