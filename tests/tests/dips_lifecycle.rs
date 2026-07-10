//! DIPs end-to-end: agreement acceptance and payment collection, driven through
//! dipper's admin RPC (`set-target-candidates`). Both mutate shared chain state
//! (nextest `alloc` group) and self-skip when the stack has no dipper.

use anyhow::Result;
use local_network_tests::TestNetwork;
use local_network_tests::dips::dips_stack_running;
use local_network_tests::dump::dump_on_failure;
use std::time::{Duration, Instant};

fn is_accepted(state: &str) -> bool {
    state.eq_ignore_ascii_case("accepted") || state.eq_ignore_ascii_case("active")
}

/// Ensure a serving allocation, warm IISA, request indexing, and wait for an
/// accepted on-chain agreement. Returns the accepted agreement's id.
async fn drive_to_accepted(net: &TestNetwork) -> Result<String> {
    let deployment = net.network_deployment().await?;
    // A proposal only goes to indexers already serving the deployment; verify
    // that precondition up front so a broken stack fails in seconds with a
    // clear message instead of burning the full agreement wait below.
    net.ensure_serving_allocation(&deployment).await?;
    net.warm_iisa().await?;
    eprintln!("=== requesting indexing for {deployment} ===");
    net.request_indexing(&deployment, 1)?;

    let deadline = Instant::now() + Duration::from_secs(300);
    loop {
        let agreements = net.dips_agreements().await?;
        for a in &agreements {
            if is_accepted(a["state"].as_str().unwrap_or("")) {
                let id = a["id"].as_str().unwrap_or("?").to_string();
                eprintln!("  ✓ agreement {id} accepted");
                return Ok(id);
            }
        }
        if Instant::now() > deadline {
            anyhow::bail!("no accepted DIPs agreement within 300s (seen: {agreements:?})");
        }
        tokio::time::sleep(Duration::from_secs(5)).await;
    }
}

#[tokio::test]
async fn dips_agreement_acceptance() -> Result<()> {
    if !dips_stack_running() {
        eprintln!("dipper not running — skipping (DIPs not enabled on this stack)");
        return Ok(());
    }
    let net = TestNetwork::from_default_env()?;
    dump_on_failure("dips_agreement_acceptance", async {
        drive_to_accepted(&net).await?;
        Ok(())
    })
    .await
}

#[tokio::test]
async fn dips_payment_collection() -> Result<()> {
    if !dips_stack_running() {
        eprintln!("dipper not running — skipping (DIPs not enabled on this stack)");
        return Ok(());
    }
    let net = TestNetwork::from_default_env()?;
    dump_on_failure("dips_payment_collection", async {
        let agreement_id = drive_to_accepted(&net).await?;
        let before = net.agreement_tokens_collected(&agreement_id).await?;
        let indexer = net.indexer_address.clone();
        eprintln!("  agreement {agreement_id} accepted; tokensCollected={before}");

        // Advance epochs/time so a collection becomes due (minSecondsPerCollection
        // is ~1h) and the agent runs it. Only tokensCollected proves a DIPs payment;
        // GRT balance is logged for context but protocol rewards move it too.
        let deadline = Instant::now() + Duration::from_secs(360);
        loop {
            net.advance_epochs(1).await?;
            net.advance_time(600).await?;
            net.mine_blocks(3).await?;

            let collected = net.agreement_tokens_collected(&agreement_id).await?;
            let balance = net.grt_balance_of(&indexer).unwrap_or(0);
            eprintln!("  poll: tokensCollected={collected} indexerBalance={balance}");
            if collected > before {
                eprintln!("  ✓ DIPs payment collected: tokensCollected {before} -> {collected}");
                return Ok(());
            }
            if Instant::now() > deadline {
                anyhow::bail!(
                    "tokensCollected did not increase within 360s (before={before}, last={collected})"
                );
            }
            tokio::time::sleep(Duration::from_secs(10)).await;
        }
    })
    .await
}
