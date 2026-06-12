//! REO Eligibility Lifecycle Tests (IndexerTestGuide Sets 2-4)
//!
//! Mapping to IndexerTestGuide:
//!   - Set 2: Eligible indexer receives rewards (renew → close → rewards > 0)
//!   - Set 3: Ineligible indexer denied rewards (close reverts under
//!     deny-by-default REO)
//!   - Set 4: Optimistic recovery (expire → re-renew → close → full rewards)
//!
//! Runs as one sequential test on a per-test indexer so the three create/close
//! cycles don't race the production agent's auto-reconciler.

use anyhow::{Context, Result};
use local_network_tests::TestNetwork;
use local_network_tests::dump::dump_on_failure;
use local_network_tests::indexer::IndexerHandle;

fn net() -> Result<TestNetwork> {
    TestNetwork::from_default_env()
}

/// Exercises REO-A's deny-by-default flow: Set 2 (eligible → close → rewards),
/// Set 3 (ineligible → close reverts), Set 4 (re-renew → rewards). Requires
/// RewardsManager to be wired to REO-A — only true under the `reo-live`
/// recipe.
///
/// History: the Set 3 → Set 4 cleanup close previously reverted "reliably"
/// with "Indexer not eligible for rewards" despite a fresh `reo_renew_indexer`.
/// That was not chain-time aging out the eligibility window (debug confirmed
/// `block.timestamp` is unchanged across renew→close) — it was an orphaned
/// per-test indexer-agent stack from a prior run interfering. The pre-up
/// `docker compose down -v --remove-orphans` in `IndexerHandle::new` removes
/// that orphan, and the cleanup close now succeeds within the eligibility
/// window.
#[tokio::test]
async fn eligibility_lifecycle() -> Result<()> {
    let net = net()?;
    if net.contracts.reo.is_none() {
        eprintln!("REO not deployed, skipping all eligibility tests");
        return Ok(());
    }
    let indexer = IndexerHandle::new("eligibility").await?;
    // Snapshot the live stack if the body fails unexpectedly, before the
    // IndexerHandle Drop tears the per-test stack down.
    dump_on_failure("eligibility_lifecycle", lifecycle(&net, &indexer)).await
}

async fn lifecycle(net: &TestNetwork, indexer: &IndexerHandle) -> Result<()> {
    let deployments = net.query_deployments_with_signal().await?;
    let deployment = deployments
        .as_array()
        .and_then(|d| d.first())
        .and_then(|d| d["ipfsHash"].as_str())
        .context("no signaled deployments")?
        .to_string();

    // Widen the eligibility period for the whole test. The agent's close
    // pipeline mines many blocks (12s of chain time each), so a default 300s
    // window can lapse between a renewal and the collect tx inside a single
    // close — making the post-renew closes (Set 2 / Set 4 / the Set 3→4
    // cleanup) intermittently revert with "not eligible for rewards". A wider
    // window (1h ≫ a close's worth of blocks) can't be outrun by one close;
    // Set 3 still proves expiry by advancing a single jump (advance_time) past
    // it. Stay well BELOW the oracle-update timeout (86400s) — expiring that
    // instead trips REO-A's fail-open (oracle-down ⇒ everyone eligible), which
    // would defeat Set 3. Restored at the end.
    let default_period = net.reo_eligibility_period()?;
    net.reo_set_eligibility_period(3_600)?;

    // ── Set 2: Eligible → close → rewards > 0 ──
    eprintln!("=== Set 2: Eligible indexer closes allocation ===");
    net.reo_renew_indexer(&indexer.address)?;
    assert!(
        net.reo_is_eligible(&indexer.address)?,
        "indexer should be eligible after renewal",
    );

    let create = indexer.create_allocation(&deployment, "0.01").await?;
    let alloc_id = create["allocation"]
        .as_str()
        .context("missing allocation id")?
        .to_string();
    net.advance_epochs(2).await?;

    // Re-renew before close — epoch advancement may have aged eligibility past period.
    net.reo_renew_indexer(&indexer.address)?;
    assert!(
        net.reo_is_eligible(&indexer.address)?,
        "indexer should still be eligible just before close",
    );

    let close = indexer.close_allocation(&alloc_id).await?;
    let eligible_rewards: f64 = close["indexingRewards"]
        .as_str()
        .unwrap_or("0")
        .parse()
        .unwrap_or(0.0);
    eprintln!("  Set 2 rewards: {eligible_rewards:.2} GRT");
    assert!(
        eligible_rewards > 0.0,
        "Set 2: eligible indexer should receive rewards",
    );

    // ── Set 3: Ineligible → close reverts (deny-by-default REO) ──
    eprintln!("=== Set 3: Ineligible indexer denied rewards ===");
    net.reo_renew_indexer(&indexer.address)?;
    let create = indexer.create_allocation(&deployment, "0.01").await?;
    let alloc_id = create["allocation"]
        .as_str()
        .context("missing allocation id")?
        .to_string();
    net.advance_epochs(2).await?;

    let period = net.reo_eligibility_period()?;
    eprintln!("  expiring eligibility ({period}s + 60s)");
    net.advance_time(period + 60).await?;
    assert!(
        !net.reo_is_eligible(&indexer.address)?,
        "indexer should be ineligible after period expiry",
    );

    // Deny-by-default: closeAllocation reverts when ineligible (the agent's
    // multicall calls collect, which checks REO.isEligible and reverts if
    // false). Verify the revert + that no rewards landed in stake.
    let stake_before = indexer.staked_tokens(net)?;
    let close_err = match indexer.close_allocation(&alloc_id).await {
        Err(e) => e,
        Ok(ok) => panic!("Set 3: expected close to revert for ineligible indexer, got {ok}"),
    };
    let close_msg = format!("{close_err:#}");
    assert!(
        close_msg.contains("not eligible for rewards"),
        "Set 3: expected eligibility error, got: {close_msg}",
    );
    eprintln!("  Set 3: close correctly reverted with eligibility error");
    let stake_after = indexer.staked_tokens(net)?;
    assert!(
        stake_after <= stake_before,
        "Set 3: stake should not change when rewards are denied (before={stake_before} after={stake_after})",
    );

    // Cleanup before Set 4: renew eligibility and close the still-open Set 3
    // allocation so we can create a fresh one for Set 4.
    net.reo_renew_indexer(&indexer.address)?;
    indexer.close_allocation(&alloc_id).await?;

    // ── Set 4: Re-renewed (optimistic recovery) → close → rewards > Set 2 ──
    eprintln!("=== Set 4: Re-renewed indexer (optimistic recovery) ===");
    net.reo_renew_indexer(&indexer.address)?;
    let create = indexer.create_allocation(&deployment, "0.01").await?;
    let alloc_id = create["allocation"]
        .as_str()
        .context("missing allocation id")?
        .to_string();
    net.advance_epochs(2).await?;

    eprintln!("  expiring eligibility");
    net.advance_time(period + 60).await?;
    assert!(!net.reo_is_eligible(&indexer.address)?);

    net.advance_epochs(2).await?; // accumulate while ineligible

    // Re-renew — the key assertion: eligibility can be restored.
    net.reo_renew_indexer(&indexer.address)?;
    assert!(
        net.reo_is_eligible(&indexer.address)?,
        "indexer should be eligible after re-renewal",
    );

    let close = indexer.close_allocation(&alloc_id).await?;
    let recovery_rewards: f64 = close["indexingRewards"]
        .as_str()
        .unwrap_or("0")
        .parse()
        .unwrap_or(0.0);
    eprintln!("  Set 4 rewards: {recovery_rewards:.2} GRT");

    // Restore the eligibility period before asserting, so a failed assertion
    // doesn't leak the widened window to later tests in the serial group.
    net.reo_set_eligibility_period(default_period)?;

    assert!(
        recovery_rewards > 0.0,
        "Set 4: re-eligible indexer should receive rewards",
    );
    assert!(
        recovery_rewards > eligible_rewards,
        "Set 4 rewards ({recovery_rewards:.2}) should exceed Set 2 rewards ({eligible_rewards:.2}) due to longer accumulation",
    );

    Ok(())
}
