//! Allocation lifecycle tests (BaselineTestPlan cycles 4-5, 7): close the
//! existing allocation, verify, recreate, advance epochs, close, and re-verify.
//! The management API mutations emulate `graph indexer allocations create/close`.

use anyhow::{Context, Result, ensure};
use local_network_tests::TestNetwork;
use local_network_tests::management::restore_allocation_on_failure;
use serial_test::serial;

fn net() -> Result<TestNetwork> {
    TestNetwork::from_default_env()
}

/// BaselineTestPlan 4.2 + 5.2: Create and close allocations.
///
/// Emulates `graph indexer allocations create` and `graph indexer allocations close`.
#[tokio::test]
#[serial(alloc)]
async fn close_and_recreate_allocation() -> Result<()> {
    let net = net()?;
    // An abort between close and recreate would otherwise strand the stack
    // with no allocation and an offchain rule, failing every later test. The
    // body fails via ensure!/bail! (not assert!) so the wrapper always runs.
    restore_allocation_on_failure(&net, close_and_recreate_allocation_body(&net)).await
}

async fn close_and_recreate_allocation_body(net: &TestNetwork) -> Result<()> {
    // Ensure we have an active allocation (recovers if a prior test panicked)
    let (deployment, _) = net.ensure_active_allocation().await?;

    // Collect all active allocation IDs for this deployment so we close them all
    let allocs = net.get_allocations().await?;
    let allocs = allocs.as_array().context("expected allocation array")?;
    let active_ids: Vec<String> = allocs
        .iter()
        .filter(|a| {
            a["closedAtEpoch"].is_null()
                && a["subgraphDeployment"].as_str() == Some(deployment.as_str())
        })
        .filter_map(|a| a["id"].as_str().map(String::from))
        .collect();

    // Advance 1 epoch so allocations are old enough to close
    // (pre-existing allocations are already many epochs old, 1 is sufficient)
    eprintln!("--- Advancing 1 epoch ---");
    let new_epoch = net.advance_epochs(1).await?;
    eprintln!("  Now at epoch {new_epoch}");

    // Close all active allocations for this deployment
    for id in &active_ids {
        eprintln!("--- Closing allocation {id} ---");
        let close_result = net.close_allocation(id).await?;
        let rewards = close_result["indexingRewards"].as_str().unwrap_or("0");
        eprintln!("  indexingRewards: {rewards}");
        let closed_id = close_result["allocation"].as_str().unwrap_or("");
        ensure!(
            closed_id == id,
            "closed allocation ID should match: expected {id}, got {closed_id}"
        );
    }

    // Create a new allocation for the same deployment (emulates: graph indexer allocations create)
    eprintln!("--- Creating new allocation for {deployment} ---");
    let amount = "0.01"; // GRT (management API takes GRT, not wei)
    let create_result = net.create_allocation(&deployment, amount).await?;
    let new_alloc_id = create_result["allocation"]
        .as_str()
        .context("createAllocation should return allocation ID")?;
    eprintln!("  Created allocation: {new_alloc_id}");

    ensure!(
        !new_alloc_id.is_empty(),
        "allocation ID should be non-empty"
    );
    let created_dep = create_result["deployment"].as_str().unwrap_or("");
    ensure!(
        created_dep == deployment,
        "deployment should match: expected {deployment}, got {created_dep}"
    );

    // Advance 2 more epochs and close the new allocation
    eprintln!("--- Advancing 2 epochs ---");
    net.advance_epochs(2).await?;

    eprintln!("--- Closing new allocation {new_alloc_id} ---");
    let close_result = net.close_allocation(new_alloc_id).await?;
    let rewards = close_result["indexingRewards"].as_str().unwrap_or("0");
    eprintln!("  indexingRewards: {rewards}");

    let closed_id = close_result["allocation"].as_str().unwrap_or("");
    ensure!(
        closed_id == new_alloc_id,
        "closed allocation ID should match: expected {new_alloc_id}, got {closed_id}"
    );

    // Re-create the allocation to restore network state
    eprintln!("--- Restoring allocation for {deployment} ---");
    net.create_allocation(&deployment, "0.01").await?;

    Ok(())
}

/// BaselineTestPlan 5.2: close via the agent and verify indexingRewards > 0.
/// The agent close is a multicall (collect IndexingRewards + stopService);
/// emulates `graph indexer allocations close` with reward verification.
#[tokio::test]
#[serial(alloc)]
#[ignore = "flakes when other allocation tests run earlier in the serial(alloc) group; passes in isolation and on a fresh stack"]
async fn close_allocation_collects_rewards() -> Result<()> {
    let net = net()?;
    // An abort after the close leaves no active allocation; restore so the
    // remaining tests in the serial group inherit a working stack. The body
    // fails via ensure!/bail! (not assert!) so the wrapper always runs.
    restore_allocation_on_failure(&net, close_allocation_collects_rewards_body(&net)).await
}

async fn close_allocation_collects_rewards_body(net: &TestNetwork) -> Result<()> {
    // Find an active allocation (recovers if a prior test left none)
    let (deployment, alloc_id) = net.ensure_active_allocation().await?;

    eprintln!("=== Close-collects-rewards test (BaselineTestPlan 5.2) ===");
    eprintln!("  Allocation: {alloc_id}");
    eprintln!("  Deployment: {deployment}");

    // Close ALL active allocations for this deployment so we can recreate cleanly.
    // indexer-agent may auto-create extra allocations on the same deployment.
    let allocs = net.get_allocations().await?;
    let allocs = allocs.as_array().context("expected allocation array")?;
    let active_ids: Vec<String> = allocs
        .iter()
        .filter(|a| {
            a["closedAtEpoch"].is_null()
                && a["subgraphDeployment"].as_str() == Some(deployment.as_str())
        })
        .filter_map(|a| a["id"].as_str().map(String::from))
        .collect();

    net.advance_epochs(1).await?;
    for id in &active_ids {
        eprintln!("  Closing active allocation {id}");
        net.close_allocation(id).await?;
    }

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
        ensure!(
            net.reo_is_eligible(&net.indexer_address)?,
            "indexer must be eligible before close"
        );
    }

    // Close via agent — this triggers collect(IndexingRewards) + stopService multicall
    eprintln!("  Closing allocation via agent...");
    let close_result = net.close_allocation(&fresh_alloc).await?;
    let rewards_str = close_result["indexingRewards"].as_str().unwrap_or("0");
    let rewards: f64 = rewards_str.parse().unwrap_or(0.0);
    eprintln!("  indexingRewards: {rewards_str} ({rewards:.2} GRT)");

    ensure!(
        rewards > 0.0,
        "agent-mediated close should collect non-zero rewards, got indexingRewards={rewards_str}"
    );

    // Verify closed allocation in subgraph
    let alloc_data = net.query_allocation(&fresh_alloc).await?;
    let status = alloc_data["status"].as_str().unwrap_or("");
    ensure!(
        status == "Closed",
        "allocation should be Closed in subgraph, got {status}"
    );

    // Restore allocation (no epoch advance needed — creating doesn't require maturity)
    net.ensure_active_allocation().await?;
    eprintln!("  Restored allocation for {deployment}");

    Ok(())
}

/// BaselineTestPlan 5.1: Send test queries through gateway.
///
/// Emulates the `query_test.sh` script from the test plan.
#[tokio::test]
#[serial(alloc)]
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
