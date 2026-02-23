//! Allocation Lifecycle Tests (BaselineTestPlan Cycles 4-5, 7)
//!
//! Exercises the allocation management and revenue collection workflow:
//!   close existing allocation → verify → create new allocation → advance → close → verify
//!
//! Mapping to BaselineTestPlan:
//!   - `close_and_recreate_allocation` → Cycle 4.2 (create) + 5.2 (close + rewards)
//!   - `close_allocation_collects_rewards` → Cycle 5.2 (agent-mediated close with reward assertion)
//!   - `gateway_query_serving` → Cycle 5.1 (query serving through gateway)
//!
//! The management API mutations (`createAllocation`, `closeAllocation`) emulate
//! what `graph indexer allocations create/close` does. The close path internally
//! triggers a multicall: collect(IndexingRewards) + stopService.

use anyhow::{Context, Result};
use local_network_tests::TestNetwork;
use serial_test::serial;

fn net() -> Result<TestNetwork> {
    TestNetwork::from_default_env()
}

/// BaselineTestPlan 4.2 + 5.2: Create and close allocations.
///
/// Emulates `graph indexer allocations create` and `graph indexer allocations close`.
#[tokio::test]
#[serial]
async fn close_and_recreate_allocation() -> Result<()> {
    let net = net()?;

    // Pick an existing active allocation to close
    let allocs = net.get_allocations().await?;
    let allocs = allocs.as_array().context("expected allocation array")?;
    let active = allocs
        .iter()
        .find(|a| a["closedAtEpoch"].is_null())
        .context("no active allocation found to close")?;
    let alloc_id = active["id"].as_str().context("allocation missing id")?;
    let deployment = active["subgraphDeployment"]
        .as_str()
        .context("allocation missing deployment")?
        .to_string();

    // Advance epochs so allocation is old enough to close
    eprintln!("--- Advancing 2 epochs ---");
    let new_epoch = net.advance_epochs(2).await?;
    eprintln!("  Now at epoch {new_epoch}");

    // Close the existing allocation (emulates: graph indexer allocations close)
    eprintln!("--- Closing allocation {alloc_id} ---");
    let close_result = net.close_allocation(alloc_id).await?;
    let rewards = close_result["indexingRewards"].as_str().unwrap_or("0");
    eprintln!("  indexingRewards: {rewards}");

    assert_eq!(
        close_result["allocation"].as_str().unwrap_or(""),
        alloc_id,
        "Closed allocation ID should match"
    );

    // Create a new allocation for the same deployment (emulates: graph indexer allocations create)
    eprintln!("--- Creating new allocation for {deployment} ---");
    let amount = "0.01"; // GRT (management API takes GRT, not wei)
    let create_result = net.create_allocation(&deployment, amount).await?;
    let new_alloc_id = create_result["allocation"]
        .as_str()
        .context("createAllocation should return allocation ID")?;
    eprintln!("  Created allocation: {new_alloc_id}");

    assert!(
        !new_alloc_id.is_empty(),
        "Allocation ID should be non-empty"
    );
    assert_eq!(
        create_result["deployment"].as_str().unwrap_or(""),
        deployment,
        "Deployment should match"
    );

    // Advance 2 more epochs and close the new allocation
    eprintln!("--- Advancing 2 epochs ---");
    net.advance_epochs(2).await?;

    eprintln!("--- Closing new allocation {new_alloc_id} ---");
    let close_result = net.close_allocation(new_alloc_id).await?;
    let rewards = close_result["indexingRewards"].as_str().unwrap_or("0");
    eprintln!("  indexingRewards: {rewards}");

    assert_eq!(
        close_result["allocation"].as_str().unwrap_or(""),
        new_alloc_id,
        "Closed allocation ID should match"
    );

    // Re-create the allocation to restore network state
    eprintln!("--- Restoring allocation for {deployment} ---");
    net.create_allocation(&deployment, "0.01").await?;

    Ok(())
}

/// BaselineTestPlan 5.2: Close allocation via agent and verify indexingRewards > 0.
///
/// The indexer-agent's close flow does a multicall: collect(IndexingRewards) + stopService.
/// This test verifies that the agent-mediated close produces non-zero rewards.
/// Emulates `graph indexer allocations close` with reward verification.
#[tokio::test]
#[serial]
async fn close_allocation_collects_rewards() -> Result<()> {
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

    eprintln!("=== Close-collects-rewards test (BaselineTestPlan 5.2) ===");
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

    // Advance epochs so rewards accumulate
    net.advance_epochs(2).await?;

    // Ensure indexer is eligible (eligibility may expire during epoch advancement)
    if net.contracts.reo.is_some() {
        net.reo_renew_indexer(&net.indexer_address)?;
        assert!(
            net.reo_is_eligible(&net.indexer_address)?,
            "Indexer must be eligible before close"
        );
    }

    // Close via agent — this triggers collect(IndexingRewards) + stopService multicall
    eprintln!("  Closing allocation via agent...");
    let close_result = net.close_allocation(&fresh_alloc).await?;
    let rewards_str = close_result["indexingRewards"].as_str().unwrap_or("0");
    let rewards: f64 = rewards_str.parse().unwrap_or(0.0);
    eprintln!("  indexingRewards: {rewards_str} ({rewards:.2} GRT)");

    assert!(
        rewards > 0.0,
        "Agent-mediated close should collect non-zero rewards. \
         Got indexingRewards={rewards_str}"
    );

    // Verify closed allocation in subgraph
    let alloc_data = net.query_allocation(&fresh_alloc).await?;
    assert_eq!(
        alloc_data["status"].as_str().unwrap_or(""),
        "Closed",
        "Allocation should be Closed in subgraph"
    );

    // Restore allocation
    net.advance_epochs(2).await?;
    net.create_allocation(&deployment, "0.01").await?;
    eprintln!("  Restored allocation for {deployment}");

    Ok(())
}

/// BaselineTestPlan 5.1: Send test queries through gateway.
///
/// Emulates the `query_test.sh` script from the test plan.
#[tokio::test]
#[serial]
async fn gateway_query_serving() -> Result<()> {
    let net = net()?;

    // Mine blocks to prevent "too far behind" errors
    net.mine_blocks(5).await?;

    eprintln!("--- Sending 10 queries through gateway ---");
    let (success, fail) = net.send_gateway_queries(10).await?;
    eprintln!("  {success} OK, {fail} failed");

    assert!(
        success >= 8,
        "At least 8/10 gateway queries should succeed, got {success}/10"
    );

    Ok(())
}
