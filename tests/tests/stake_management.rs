//! Stake Management Tests (BaselineTestPlan Cycle 2)
//!
//! Tests adding and removing stake from the indexer.
//! In production, these operations are performed via Explorer UI;
//! here we emulate them with direct HorizonStaking contract calls.
//!
//! Mapping to BaselineTestPlan:
//!   - `add_stake` → Cycle 2.1 (Add stake via Explorer)
//!   - `unstake_idle_tokens` → Cycle 2.2 (Unstake tokens)

use anyhow::Result;
use local_network_tests::TestNetwork;
use serial_test::serial;

fn net() -> Result<TestNetwork> {
    TestNetwork::from_default_env()
}

/// BaselineTestPlan 2.1: Add stake to indexer.
///
/// Emulates Explorer "Add Stake": approve GRT → stakeTo(indexer, amount).
/// Verifies stakedTokens increases after staking.
#[tokio::test]
#[serial]
async fn add_stake() -> Result<()> {
    let net = net()?;
    eprintln!("=== BaselineTestPlan 2.1: Add Stake ===");

    let before = net.staked_tokens()?;
    eprintln!("  Staked before: {before}");

    let amount = "1000000000000000000000"; // 1000 GRT
    net.stake_tokens(amount)?;

    let after = net.staked_tokens()?;
    let delta = after.saturating_sub(before);
    eprintln!("  Staked after: {after} (+{delta} wei)");

    assert!(
        after > before,
        "stakedTokens should increase after adding stake. Before: {before}, After: {after}"
    );

    Ok(())
}

/// BaselineTestPlan 2.2: Unstake idle tokens.
///
/// Emulates Explorer "Unstake": adds idle stake, then calls unstake().
/// Verifies stakedTokens decreases after unstaking.
///
/// Note: This only unstakes idle (unprovisioned) tokens. Full thawing
/// and withdrawal after the thawing period is tested in provision_management.
#[tokio::test]
#[serial]
async fn unstake_idle_tokens() -> Result<()> {
    let net = net()?;
    eprintln!("=== BaselineTestPlan 2.2: Unstake Tokens ===");

    // Add some stake to create idle (unprovisioned) tokens
    let amount = "1000000000000000000000"; // 1000 GRT
    net.stake_tokens(amount)?;

    let idle = net.idle_stake()?;
    eprintln!("  Idle stake after adding: {idle}");
    assert!(idle > 0, "Should have idle stake to unstake");

    // Unstake the idle portion
    let before = net.staked_tokens()?;
    net.unstake_tokens(amount)?;
    let after = net.staked_tokens()?;
    eprintln!("  Staked before unstake: {before}");
    eprintln!("  Staked after unstake: {after}");

    assert!(
        after < before,
        "stakedTokens should decrease after unstaking. Before: {before}, After: {after}"
    );

    Ok(())
}
