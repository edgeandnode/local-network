//! Allocation Lifecycle Tests (BaselineTestPlan Cycles 4-5, 7)
//!
//! Exercises the allocation management and revenue collection workflow.
//! Allocation-mutating tests use a per-test `IndexerHandle` so they don't
//! race the production indexer's auto-reconciler. Tests that observe the
//! production stack (gateway routing) keep using `TestNetwork` directly.
//!
//! Mapping:
//!   - `close_and_recreate_allocation`     → Cycle 4.2 (create) + 5.2 (close)
//!   - `close_allocation_collects_rewards` → Cycle 5.2 (close + reward assertion)
//!   - `gateway_query_serving`             → Cycle 5.1 (query serving — production)

use anyhow::{Context, Result};
use local_network_tests::TestNetwork;
use local_network_tests::indexer::IndexerHandle;
use serial_test::serial;

fn net() -> Result<TestNetwork> {
    TestNetwork::from_default_env()
}

/// BaselineTestPlan 4.2 + 5.2: create → advance → close → recreate.
#[tokio::test]
#[serial(alloc)]
async fn close_and_recreate_allocation() -> Result<()> {
    let net = net()?;
    let indexer = IndexerHandle::new("close-recreate").await?;

    // Pick any signaled deployment — main and the per-test graph-node both
    // index the network subgraph from the same chain.
    let deployments = net.query_deployments_with_signal().await?;
    let deployment = deployments
        .as_array()
        .and_then(|d| d.first())
        .and_then(|d| d["ipfsHash"].as_str())
        .context("no signaled deployments found in network subgraph")?
        .to_string();
    eprintln!("Using deployment {deployment}");

    let create = indexer.create_allocation(&deployment, "0.01").await?;
    let alloc_id = create["allocation"]
        .as_str()
        .context("createAllocation missing allocation id")?
        .to_string();
    eprintln!("Created allocation {alloc_id}");

    net.advance_epochs(1).await?;

    // closeAllocation calls collect() which reverts if the indexer is
    // ineligible. Refresh eligibility before close.
    if net.contracts.reo.is_some() {
        net.reo_renew_indexer(&indexer.address)?;
    }

    let close = indexer.close_allocation(&alloc_id).await?;
    eprintln!("Close result: {close}");
    assert_eq!(
        close["allocation"].as_str(),
        Some(alloc_id.as_str()),
        "closed allocation id should match",
    );

    // The agent's pre-flight check for createAllocation queries its own state
    // for active allocations on the deployment. Even after a successful close,
    // the network subgraph view (which the agent re-queries on createAllocation)
    // can lag a few seconds behind the close tx. Poll until the closed
    // allocation is no longer reported active.
    //
    // `indexerAllocations` filters to status=Active server-side and nests the
    // deployment as { id, stakedTokens, signalledTokens } — match on the
    // nested .id.
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(60);
    loop {
        let allocs = indexer.get_allocations().await?;
        let still_active = allocs
            .as_array()
            .map(|a| {
                a.iter().any(|alloc| {
                    alloc["subgraphDeployment"]["id"].as_str() == Some(deployment.as_str())
                })
            })
            .unwrap_or(false);
        if !still_active {
            break;
        }
        if std::time::Instant::now() >= deadline {
            anyhow::bail!("agent still reports active allocation on {deployment} after close");
        }
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
    }

    let new = indexer.create_allocation(&deployment, "0.005").await?;
    let new_id = new["allocation"].as_str().context("new allocation id")?;
    eprintln!("Recreated allocation {new_id}");
    assert!(!new_id.is_empty(), "new allocation id should be non-empty");

    Ok(())
}

/// BaselineTestPlan 5.2: agent-mediated close (collect+stopService multicall)
/// produces non-zero indexingRewards.
#[tokio::test]
#[serial(alloc)]
async fn close_allocation_collects_rewards() -> Result<()> {
    let net = net()?;
    let indexer = IndexerHandle::new("close-collects").await?;

    let deployments = net.query_deployments_with_signal().await?;
    let deployment = deployments
        .as_array()
        .and_then(|d| d.first())
        .and_then(|d| d["ipfsHash"].as_str())
        .context("no signaled deployments found")?
        .to_string();

    let create = indexer.create_allocation(&deployment, "0.01").await?;
    let alloc_id = create["allocation"]
        .as_str()
        .context("missing allocation id")?
        .to_string();
    eprintln!("Created allocation {alloc_id}");

    net.advance_epochs(2).await?;

    // REO eligibility may expire during epoch advancement; renew before close
    // so collect() doesn't revert.
    if net.contracts.reo.is_some() {
        net.reo_renew_indexer(&indexer.address)?;
        assert!(
            net.reo_is_eligible(&indexer.address)?,
            "indexer must be eligible before close",
        );
    }

    let close = indexer.close_allocation(&alloc_id).await?;
    let rewards_str = close["indexingRewards"].as_str().unwrap_or("0");
    let rewards: f64 = rewards_str.parse().unwrap_or(0.0);
    eprintln!("Close result: rewards={rewards_str} ({rewards:.2} GRT)");

    assert!(
        rewards > 0.0,
        "agent-mediated close should collect non-zero rewards (got {rewards_str})",
    );

    let alloc_data = net.query_allocation(&alloc_id).await?;
    assert_eq!(
        alloc_data["status"].as_str(),
        Some("Closed"),
        "allocation should be Closed in the network subgraph",
    );

    Ok(())
}

/// BaselineTestPlan 5.1: queries through the gateway succeed against the
/// production indexer (the gateway routes by allocation in the network
/// subgraph; it doesn't know about per-test indexers).
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
