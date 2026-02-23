//! REO Eligibility Lifecycle Tests (IndexerTestGuide Sets 2-4)
//!
//! Mapping to IndexerTestGuide:
//!   - Set 2: Eligible indexer receives rewards (renew → close → rewards > 0)
//!   - Set 3: Ineligible indexer denied rewards (expire → close → rewards = 0)
//!   - Set 4: Optimistic recovery (expire → re-renew → close → full rewards)
//!
//! Uses deterministic contract calls via `renewIndexerEligibility` (account0 has
//! ORACLE_ROLE) and `evm_increaseTime` to expire eligibility periods.
//!
//! These tests share mutable chain state (allocations, eligibility, epoch) so they
//! run as a single sequential test to avoid races.
//!
//! No dependency on the REO node's async processing.

use anyhow::{Context, Result};
use local_network_tests::TestNetwork;

fn net() -> Result<TestNetwork> {
    TestNetwork::from_default_env()
}

/// Parse a reward string (may be "0", "0.0", "123.456", etc.) to f64.
fn parse_rewards(s: &str) -> f64 {
    s.parse::<f64>().unwrap_or(0.0)
}

/// Helper: close an existing active allocation and return (deployment, alloc_id).
/// This frees the deployment for a new allocation.
async fn close_existing_allocation(net: &TestNetwork) -> Result<(String, String)> {
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

    // Advance epochs so allocation is old enough to close
    net.advance_epochs(2).await?;
    net.close_allocation(&alloc_id).await?;

    Ok((deployment, alloc_id))
}

/// Helper: create allocation, advance epochs, and return the allocation ID.
async fn create_test_allocation(net: &TestNetwork, deployment: &str) -> Result<String> {
    let amount = "0.01"; // GRT (management API takes GRT, not wei)
    let result = net.create_allocation(deployment, amount).await?;
    let alloc_id = result["allocation"]
        .as_str()
        .context("expected allocation ID")?
        .to_string();

    // Advance epochs so it's old enough to close
    net.advance_epochs(2).await?;

    Ok(alloc_id)
}

/// IndexerTestGuide Sets 2, 3, and 4: Complete eligibility lifecycle.
///
/// Runs sequentially to avoid shared-state races.
/// Each section maps to an IndexerTestGuide set:
///   - Set 2.1: `renewIndexerEligibility` → `isEligible` = true
///   - Set 2.2: close allocation → `indexingRewards` > 0
///   - Set 3.1: advance past eligibility period → `isEligible` = false
///   - Set 3.2: close allocation → `indexingRewards` = 0
///   - Set 4.1: `renewIndexerEligibility` → `isEligible` = true (re-renewal)
///   - Set 4.2: close allocation → rewards > 0 AND > Set 2 rewards (optimistic)
#[tokio::test]
async fn eligibility_lifecycle() -> Result<()> {
    let net = net()?;
    if net.contracts.reo.is_none() {
        eprintln!("REO not deployed, skipping all eligibility tests");
        return Ok(());
    }

    // Free up a deployment by closing an existing allocation
    eprintln!("=== Setup: close existing allocation to free a deployment ===");
    let (deployment, _) = close_existing_allocation(&net).await?;
    eprintln!("  Deployment: {deployment}");

    // ── Set 2: Eligible → close → verify rewards received ──
    eprintln!();
    eprintln!("=== Set 2: Eligible indexer closes allocation ===");

    net.reo_renew_indexer(&net.indexer_address)?;
    assert!(
        net.reo_is_eligible(&net.indexer_address)?,
        "Indexer should be eligible after renewal"
    );

    let alloc_id = create_test_allocation(&net, &deployment).await?;
    eprintln!("  Allocation: {alloc_id}");

    // Re-renew to ensure still eligible (time advanced during epoch mining)
    net.reo_renew_indexer(&net.indexer_address)?;
    assert!(
        net.reo_is_eligible(&net.indexer_address)?,
        "Indexer should still be eligible before close"
    );

    let close = net.close_allocation(&alloc_id).await?;
    let rewards = close["indexingRewards"].as_str().unwrap_or("0");
    let eligible_rewards = parse_rewards(rewards);
    eprintln!("  indexingRewards: {rewards} (eligible)");
    assert!(
        eligible_rewards > 0.0,
        "Set 2: Eligible indexer should receive rewards, got {rewards}"
    );

    // ── Set 3: Ineligible → close → verify rewards denied ──
    eprintln!();
    eprintln!("=== Set 3: Ineligible indexer denied rewards ===");

    net.reo_renew_indexer(&net.indexer_address)?;
    let alloc_id = create_test_allocation(&net, &deployment).await?;
    eprintln!("  Allocation: {alloc_id}");

    // Expire eligibility
    let period = net.reo_eligibility_period()?;
    eprintln!("  Advancing time by {period}s + 60s to expire eligibility");
    net.advance_time(period + 60).await?;

    assert!(
        !net.reo_is_eligible(&net.indexer_address)?,
        "Set 3: Indexer should be ineligible after period expiry"
    );

    // ReoTestPlan 6.3: Record stake before closing while ineligible
    let stake_before_denied = net.staked_tokens()?;

    let close = net.close_allocation(&alloc_id).await?;
    let rewards = close["indexingRewards"].as_str().unwrap_or("0");
    let ineligible_rewards = parse_rewards(rewards);
    eprintln!("  indexingRewards: {rewards} (ineligible)");
    assert!(
        ineligible_rewards == 0.0,
        "Set 3: Ineligible indexer should receive zero rewards, got {rewards}"
    );

    // ReoTestPlan 6.3: Verify stake did not increase (denied rewards not credited)
    let stake_after_denied = net.staked_tokens()?;
    eprintln!(
        "  Staked tokens: {stake_before_denied} → {stake_after_denied} (should not increase)"
    );
    assert!(
        stake_after_denied <= stake_before_denied,
        "Set 3 / ReoTestPlan 6.3: Stake should not increase when rewards are denied. \
         Before: {stake_before_denied}, After: {stake_after_denied}"
    );

    // ── Set 4: Optimistic recovery → re-renew → verify re-eligibility ──
    eprintln!();
    eprintln!("=== Set 4: Re-renewed indexer (optimistic recovery) ===");

    net.reo_renew_indexer(&net.indexer_address)?;
    let alloc_id = create_test_allocation(&net, &deployment).await?;
    eprintln!("  Allocation: {alloc_id}");

    // Let eligibility expire
    eprintln!("  Expiring eligibility ({period}s)...");
    net.advance_time(period + 60).await?;
    assert!(
        !net.reo_is_eligible(&net.indexer_address)?,
        "Should be ineligible"
    );

    // Advance more epochs while ineligible
    net.advance_epochs(2).await?;

    // Re-renew — the key assertion: eligibility can be restored
    net.reo_renew_indexer(&net.indexer_address)?;
    assert!(
        net.reo_is_eligible(&net.indexer_address)?,
        "Should be eligible after re-renewal"
    );

    let close = net.close_allocation(&alloc_id).await?;
    let rewards = close["indexingRewards"].as_str().unwrap_or("0");
    let recovery_rewards = parse_rewards(rewards);
    eprintln!("  indexingRewards: {rewards} (re-eligible)");
    assert!(
        recovery_rewards > 0.0,
        "Set 4: Re-eligible indexer should receive rewards, got {rewards}"
    );
    assert!(
        recovery_rewards > eligible_rewards,
        "Set 4: Re-eligible rewards ({recovery_rewards}) should exceed \
         Set 2 rewards ({eligible_rewards}) due to longer accumulation"
    );

    // Restore: re-create the allocation we consumed
    eprintln!();
    eprintln!("=== Cleanup: restoring allocation for {deployment} ===");
    net.create_allocation(&deployment, "0.01").await?;

    Ok(())
}
