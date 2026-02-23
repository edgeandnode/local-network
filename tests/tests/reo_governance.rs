//! REO Governance & Coordinator Tests (ReoTestPlan Cycles 1, 3, 4, 5, 7)
//!
//! Tests the coordinator/governance operations on the RewardsEligibilityOracle:
//! deployment verification, oracle operations, validation toggle, timeout
//! fail-open, pause/unpause, and access control.
//!
//! These are operations performed by the protocol team (not indexers).
//! On the local network, account0 holds all privileged roles.
//!
//! Mapping to ReoTestPlan:
//!   - `deployment_parameters` → Cycle 1.3 (default config)
//!   - `rewards_manager_integration` → Cycle 1.4 (RewardsManager → REO)
//!   - `contract_not_paused` → Cycle 1.5
//!   - `renew_single_indexer` → Cycle 3.2
//!   - `batch_renewal` → Cycle 3.3
//!   - `zero_address_skipped` → Cycle 3.4
//!   - `unauthorized_renewal_reverts` → Cycle 3.5
//!   - `enable_validation_eligible_stays` → Cycle 4.1 + 4.2
//!   - `eligibility_expires_after_period` → Cycle 4.4
//!   - `timeout_failopen` → Cycle 5.1
//!   - `oracle_renewal_resets_timeout` → Cycle 5.2
//!   - `pause_blocks_writes` → Cycle 7.1
//!   - `disable_validation_emergency` → Cycle 7.2
//!   - `access_control_unauthorized` → Cycle 7.3

use anyhow::{Context, Result};
use local_network_tests::TestNetwork;
use serial_test::serial;

fn net() -> Result<TestNetwork> {
    TestNetwork::from_default_env()
}

/// A private key for an account with NO roles on the REO contract.
/// Hardhat account #9 — has ETH but no governance roles.
const UNAUTHORIZED_KEY: &str = "0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6";

// ── Cycle 1: Deployment Verification ──

/// ReoTestPlan 1.3: Verify default parameters.
#[tokio::test]
#[serial]
async fn deployment_parameters() -> Result<()> {
    let net = net()?;
    if net.contracts.reo.is_none() {
        eprintln!("REO not deployed, skipping");
        return Ok(());
    }

    eprintln!("=== ReoTestPlan 1.3: Deployment Parameters ===");

    let period = net.reo_eligibility_period()?;
    eprintln!("  eligibilityPeriod: {period}s");
    assert!(period > 0, "eligibilityPeriod should be > 0");

    let timeout = net.reo_oracle_timeout()?;
    eprintln!("  oracleUpdateTimeout: {timeout}s");
    assert!(timeout > 0, "oracleUpdateTimeout should be > 0");

    let validation = net.reo_validation_enabled()?;
    eprintln!("  eligibilityValidation: {validation}");
    // On local network, validation is pre-enabled by setup

    Ok(())
}

/// ReoTestPlan 1.4: RewardsManager points to the REO contract.
#[tokio::test]
#[serial]
async fn rewards_manager_integration() -> Result<()> {
    let net = net()?;
    let reo = match &net.contracts.reo {
        Some(addr) => addr.clone(),
        None => {
            eprintln!("REO not deployed, skipping");
            return Ok(());
        }
    };

    eprintln!("=== ReoTestPlan 1.4: RewardsManager Integration ===");

    let configured_reo = net.rewards_manager_reo_address()?;
    eprintln!("  RewardsManager.getRewardsEligibilityOracle(): {configured_reo}");
    eprintln!("  Expected REO address: {reo}");

    assert_eq!(
        configured_reo.to_lowercase(),
        reo.to_lowercase(),
        "RewardsManager should point to the REO contract"
    );

    Ok(())
}

/// ReoTestPlan 1.5: Contract is not paused.
#[tokio::test]
#[serial]
async fn contract_not_paused() -> Result<()> {
    let net = net()?;
    if net.contracts.reo.is_none() {
        eprintln!("REO not deployed, skipping");
        return Ok(());
    }

    eprintln!("=== ReoTestPlan 1.5: Contract Not Paused ===");

    let paused = net.reo_is_paused()?;
    eprintln!("  paused: {paused}");
    assert!(!paused, "REO should not be paused");

    Ok(())
}

// ── Cycle 3: Oracle Operations ──

/// ReoTestPlan 3.2: Renew single indexer and verify timestamps + events.
#[tokio::test]
#[serial]
async fn renew_single_indexer() -> Result<()> {
    let net = net()?;
    let reo = match &net.contracts.reo {
        Some(addr) => addr.clone(),
        None => {
            eprintln!("REO not deployed, skipping");
            return Ok(());
        }
    };

    eprintln!("=== ReoTestPlan 3.2: Renew Single Indexer ===");

    let before_oracle = net.reo_last_oracle_update()?;
    let before_renewal = net.reo_renewal_time(&net.indexer_address)?;

    // Record block before renewal for event verification
    let block_before = net.get_block_number_sync()?;

    net.reo_renew_indexer(&net.indexer_address)?;

    let block_after = net.get_block_number_sync()?;
    let after_oracle = net.reo_last_oracle_update()?;
    let after_renewal = net.reo_renewal_time(&net.indexer_address)?;

    eprintln!("  lastOracleUpdateTime: {before_oracle} → {after_oracle}");
    eprintln!("  renewalTime({}):", net.indexer_address);
    eprintln!("    before: {before_renewal}");
    eprintln!("    after:  {after_renewal}");

    assert!(
        after_oracle >= before_oracle,
        "lastOracleUpdateTime should not decrease"
    );
    assert!(after_renewal > 0, "renewalTime should be set after renewal");
    assert!(
        after_renewal >= before_renewal,
        "renewalTime should not decrease"
    );

    assert!(
        net.reo_is_eligible(&net.indexer_address)?,
        "Indexer should be eligible after renewal"
    );

    // Event verification: check for IndexerEligibilityRenewed event
    let logs = net.cast_logs_json(&reo, block_before, block_after)?;
    eprintln!(
        "  Events emitted: {} log(s) in blocks {block_before}..{block_after}",
        logs.len()
    );
    assert!(
        !logs.is_empty(),
        "renewIndexerEligibility should emit events"
    );

    let renewed_topic = net.cast_keccak("IndexerEligibilityRenewed(address,address)")?;
    let has_renewed_event = logs.iter().any(|log| {
        log["topics"]
            .as_array()
            .and_then(|t| t.first())
            .and_then(|t| t.as_str())
            .is_some_and(|t| t == renewed_topic)
    });
    eprintln!("  IndexerEligibilityRenewed event: {has_renewed_event}");
    assert!(
        has_renewed_event,
        "Should emit IndexerEligibilityRenewed event"
    );

    Ok(())
}

/// ReoTestPlan 3.3: Batch renewal of multiple addresses.
#[tokio::test]
#[serial]
async fn batch_renewal() -> Result<()> {
    let net = net()?;
    if net.contracts.reo.is_none() {
        eprintln!("REO not deployed, skipping");
        return Ok(());
    }

    eprintln!("=== ReoTestPlan 3.3: Batch Renewal ===");

    // Use the indexer plus two arbitrary addresses
    let addr1 = &net.indexer_address;
    let addr2 = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"; // Hardhat #1
    let addr3 = "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"; // Hardhat #2

    net.reo_renew_batch(&[addr1, addr2, addr3])?;

    let t1 = net.reo_renewal_time(addr1)?;
    let t2 = net.reo_renewal_time(addr2)?;
    let t3 = net.reo_renewal_time(addr3)?;
    eprintln!("  renewalTime({addr1}): {t1}");
    eprintln!("  renewalTime({addr2}): {t2}");
    eprintln!("  renewalTime({addr3}): {t3}");

    assert!(t1 > 0, "addr1 should have renewal timestamp");
    assert!(t2 > 0, "addr2 should have renewal timestamp");
    assert!(t3 > 0, "addr3 should have renewal timestamp");

    Ok(())
}

/// ReoTestPlan 3.4: Zero addresses silently skipped in renewal.
#[tokio::test]
#[serial]
async fn zero_address_skipped() -> Result<()> {
    let net = net()?;
    if net.contracts.reo.is_none() {
        eprintln!("REO not deployed, skipping");
        return Ok(());
    }

    eprintln!("=== ReoTestPlan 3.4: Zero Address Skipped ===");

    let zero = "0x0000000000000000000000000000000000000000";
    // Should succeed (zero address is silently skipped)
    net.reo_renew_batch(&[zero, &net.indexer_address])?;

    let zero_time = net.reo_renewal_time(zero)?;
    let indexer_time = net.reo_renewal_time(&net.indexer_address)?;
    eprintln!("  renewalTime(zero): {zero_time}");
    eprintln!("  renewalTime(indexer): {indexer_time}");

    assert_eq!(zero_time, 0, "Zero address should not get a renewal time");
    assert!(indexer_time > 0, "Indexer should still get renewed");

    Ok(())
}

/// ReoTestPlan 3.5: Unauthorized account cannot renew.
#[tokio::test]
#[serial]
async fn unauthorized_renewal_reverts() -> Result<()> {
    let net = net()?;
    let reo = match &net.contracts.reo {
        Some(addr) => addr.clone(),
        None => {
            eprintln!("REO not deployed, skipping");
            return Ok(());
        }
    };

    eprintln!("=== ReoTestPlan 3.5: Unauthorized Renewal Reverts ===");

    let array = format!("[{}]", net.indexer_address);
    let succeeded = net.cast_send_may_revert(
        UNAUTHORIZED_KEY,
        &reo,
        "renewIndexerEligibility(address[],bytes)",
        &[&array, "0x"],
    )?;

    eprintln!("  Unauthorized renewal succeeded: {succeeded}");
    assert!(
        !succeeded,
        "Renewal from unauthorized account should revert"
    );

    Ok(())
}

// ── Cycle 4: Validation Toggle ──

/// ReoTestPlan 4.1 + 4.2: Enable validation, verify renewed indexer stays eligible.
///
/// Saves and restores the original validation state.
#[tokio::test]
#[serial]
async fn enable_validation_eligible_stays() -> Result<()> {
    let net = net()?;
    if net.contracts.reo.is_none() {
        eprintln!("REO not deployed, skipping");
        return Ok(());
    }

    eprintln!("=== ReoTestPlan 4.1 + 4.2: Enable Validation ===");

    let original = net.reo_validation_enabled()?;

    // Ensure indexer is renewed
    net.reo_renew_indexer(&net.indexer_address)?;

    // Enable validation
    net.reo_set_validation(true)?;
    assert!(
        net.reo_validation_enabled()?,
        "Validation should be enabled"
    );

    // Renewed indexer should still be eligible
    let eligible = net.reo_is_eligible(&net.indexer_address)?;
    eprintln!("  isEligible after enabling validation: {eligible}");
    assert!(
        eligible,
        "Renewed indexer should remain eligible after enabling validation"
    );

    // Restore original state
    net.reo_set_validation(original)?;

    Ok(())
}

/// ReoTestPlan 4.4: Eligibility expires after period.
///
/// Reduces the period to 60s, renews, waits, verifies expiry, then restores.
#[tokio::test]
#[serial]
async fn eligibility_expires_after_period() -> Result<()> {
    let net = net()?;
    if net.contracts.reo.is_none() {
        eprintln!("REO not deployed, skipping");
        return Ok(());
    }

    eprintln!("=== ReoTestPlan 4.4: Eligibility Expires After Period ===");

    let original_period = net.reo_eligibility_period()?;
    let original_validation = net.reo_validation_enabled()?;

    // Enable validation and set short period
    net.reo_set_validation(true)?;
    net.reo_set_eligibility_period(60)?;
    eprintln!("  Set eligibilityPeriod to 60s");

    // Renew indexer
    net.reo_renew_indexer(&net.indexer_address)?;
    assert!(
        net.reo_is_eligible(&net.indexer_address)?,
        "Should be eligible immediately after renewal"
    );

    // Advance past the 60s period
    net.advance_time(65).await?;

    let eligible = net.reo_is_eligible(&net.indexer_address)?;
    eprintln!("  isEligible after 65s: {eligible}");
    assert!(!eligible, "Should be ineligible after period expires");

    // Restore original state
    net.reo_set_eligibility_period(original_period)?;
    net.reo_set_validation(original_validation)?;
    // Re-renew to restore eligibility
    net.reo_renew_indexer(&net.indexer_address)?;
    eprintln!("  Restored period={original_period}s, validation={original_validation}");

    Ok(())
}

// ── Cycle 5: Timeout Fail-Open ──

/// ReoTestPlan 5.1: Oracle timeout makes all indexers eligible (fail-open).
///
/// Reduces timeout to 60s, lets it expire, verifies an unrenewed address
/// becomes eligible via the fail-open mechanism.
#[tokio::test]
#[serial]
async fn timeout_failopen() -> Result<()> {
    let net = net()?;
    if net.contracts.reo.is_none() {
        eprintln!("REO not deployed, skipping");
        return Ok(());
    }

    eprintln!("=== ReoTestPlan 5.1: Timeout Fail-Open ===");

    let original_timeout = net.reo_oracle_timeout()?;
    let original_validation = net.reo_validation_enabled()?;

    // Use an address that has never been renewed
    let never_renewed = "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65"; // Hardhat #4

    // Enable validation so non-renewed addresses are ineligible
    net.reo_set_validation(true)?;

    // Renew the main indexer (to set lastOracleUpdateTime)
    net.reo_renew_indexer(&net.indexer_address)?;

    // Verify the never-renewed address is NOT eligible
    let before = net.reo_is_eligible(never_renewed)?;
    eprintln!("  isEligible({never_renewed}) before timeout: {before}");
    assert!(!before, "Never-renewed address should be ineligible");

    // Reduce timeout to 60s and wait
    net.reo_set_oracle_timeout(60)?;
    eprintln!("  Set oracleUpdateTimeout to 60s");

    net.advance_time(65).await?;

    // Now the fail-open should kick in
    let after = net.reo_is_eligible(never_renewed)?;
    eprintln!("  isEligible({never_renewed}) after timeout: {after}");
    assert!(
        after,
        "Never-renewed address should be eligible via fail-open after oracle timeout"
    );

    // Restore
    net.reo_set_oracle_timeout(original_timeout)?;
    net.reo_set_validation(original_validation)?;
    net.reo_renew_indexer(&net.indexer_address)?;
    eprintln!("  Restored timeout={original_timeout}s, validation={original_validation}");

    Ok(())
}

/// ReoTestPlan 5.2: Oracle renewal resets the timeout clock.
#[tokio::test]
#[serial]
async fn oracle_renewal_resets_timeout() -> Result<()> {
    let net = net()?;
    if net.contracts.reo.is_none() {
        eprintln!("REO not deployed, skipping");
        return Ok(());
    }

    eprintln!("=== ReoTestPlan 5.2: Oracle Renewal Resets Timeout ===");

    let before = net.reo_last_oracle_update()?;
    let ts_before = net.get_block_timestamp()?;
    eprintln!("  lastOracleUpdateTime before: {before}");
    eprintln!("  block.timestamp before: {ts_before}");

    // Advance time so we can see a clear difference
    net.advance_time(30).await?;

    // Renew — this should update lastOracleUpdateTime
    net.reo_renew_indexer(&net.indexer_address)?;

    let after = net.reo_last_oracle_update()?;
    let ts_after = net.get_block_timestamp()?;
    eprintln!("  lastOracleUpdateTime after: {after}");
    eprintln!("  block.timestamp after: {ts_after}");

    assert!(
        after > before,
        "lastOracleUpdateTime should increase after renewal. Before: {before}, After: {after}"
    );

    Ok(())
}

// ── Cycle 7: Emergency Operations ──

/// ReoTestPlan 7.1: Pause blocks writes, view functions still work.
///
/// Pauses, verifies writes revert, reads still work, then unpauses.
#[tokio::test]
#[serial]
async fn pause_blocks_writes() -> Result<()> {
    let net = net()?;
    let reo = match &net.contracts.reo {
        Some(addr) => addr.clone(),
        None => {
            eprintln!("REO not deployed, skipping");
            return Ok(());
        }
    };

    eprintln!("=== ReoTestPlan 7.1: Pause Blocks Writes ===");

    // Pause
    net.reo_pause()?;
    assert!(net.reo_is_paused()?, "Should be paused");
    eprintln!("  Paused: true");

    // View functions should still work
    let eligible = net.reo_is_eligible(&net.indexer_address)?;
    eprintln!("  isEligible (while paused): {eligible}");
    // No assertion on the value — just that it doesn't revert

    // Write should revert while paused
    let array = format!("[{}]", net.indexer_address);
    let succeeded = net.cast_send_may_revert(
        &net.account0_secret,
        &reo,
        "renewIndexerEligibility(address[],bytes)",
        &[&array, "0x"],
    )?;
    eprintln!("  renewIndexerEligibility while paused succeeded: {succeeded}");
    assert!(
        !succeeded,
        "renewIndexerEligibility should revert while paused"
    );

    // Unpause
    net.reo_unpause()?;
    assert!(!net.reo_is_paused()?, "Should be unpaused");
    eprintln!("  Unpaused: true");

    // Writes should work again
    net.reo_renew_indexer(&net.indexer_address)?;
    eprintln!("  Renewal after unpause: OK");

    Ok(())
}

/// ReoTestPlan 7.2: Disable validation makes all indexers eligible.
#[tokio::test]
#[serial]
async fn disable_validation_emergency() -> Result<()> {
    let net = net()?;
    if net.contracts.reo.is_none() {
        eprintln!("REO not deployed, skipping");
        return Ok(());
    }

    eprintln!("=== ReoTestPlan 7.2: Disable Validation (Emergency) ===");

    let original = net.reo_validation_enabled()?;

    // Enable validation first
    net.reo_set_validation(true)?;

    // An address that was never renewed should be ineligible
    let never_renewed = "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65";
    // Renew the main indexer so lastOracleUpdateTime is fresh (prevent fail-open)
    net.reo_renew_indexer(&net.indexer_address)?;

    let before = net.reo_is_eligible(never_renewed)?;
    eprintln!("  isEligible({never_renewed}) with validation on: {before}");
    assert!(
        !before,
        "Never-renewed should be ineligible with validation on"
    );

    // Disable validation — emergency override
    net.reo_set_validation(false)?;

    let after = net.reo_is_eligible(never_renewed)?;
    eprintln!("  isEligible({never_renewed}) with validation off: {after}");
    assert!(
        after,
        "All indexers should be eligible when validation is disabled"
    );

    // Restore
    net.reo_set_validation(original)?;
    net.reo_renew_indexer(&net.indexer_address)?;

    Ok(())
}

/// ReoTestPlan 7.3: Unauthorized accounts cannot perform governance operations.
#[tokio::test]
#[serial]
async fn access_control_unauthorized() -> Result<()> {
    let net = net()?;
    let reo = match &net.contracts.reo {
        Some(addr) => addr.clone(),
        None => {
            eprintln!("REO not deployed, skipping");
            return Ok(());
        }
    };

    eprintln!("=== ReoTestPlan 7.3: Access Control ===");

    // Non-operator cannot set eligibility period
    let ok = net.cast_send_may_revert(
        UNAUTHORIZED_KEY,
        &reo,
        "setEligibilityPeriod(uint256)",
        &["100"],
    )?;
    eprintln!("  setEligibilityPeriod (unauthorized): succeeded={ok}");
    assert!(!ok, "setEligibilityPeriod should revert for non-operator");

    // Non-operator cannot enable validation
    let ok = net.cast_send_may_revert(
        UNAUTHORIZED_KEY,
        &reo,
        "setEligibilityValidation(bool)",
        &["true"],
    )?;
    eprintln!("  setEligibilityValidation (unauthorized): succeeded={ok}");
    assert!(
        !ok,
        "setEligibilityValidation should revert for non-operator"
    );

    // Non-pause-role cannot pause
    let ok = net.cast_send_may_revert(UNAUTHORIZED_KEY, &reo, "pause()", &[])?;
    eprintln!("  pause (unauthorized): succeeded={ok}");
    assert!(!ok, "pause should revert for non-pause-role");

    // Non-operator cannot set oracle timeout
    let ok = net.cast_send_may_revert(
        UNAUTHORIZED_KEY,
        &reo,
        "setOracleUpdateTimeout(uint256)",
        &["100"],
    )?;
    eprintln!("  setOracleUpdateTimeout (unauthorized): succeeded={ok}");
    assert!(!ok, "setOracleUpdateTimeout should revert for non-operator");

    Ok(())
}

// ── Cycle 6: Rewards Integration (View Functions) ──

/// ReoTestPlan 6.5: View functions reflect zero for ineligible indexer.
///
/// When an indexer is ineligible, `RewardsManager.getRewards()` should
/// return 0 for their active allocations, preventing the UI from
/// displaying unclaimable rewards.
///
/// Saves and restores the original validation state.
#[tokio::test]
#[serial]
async fn rewards_view_zero_for_ineligible() -> Result<()> {
    let net = net()?;
    if net.contracts.reo.is_none() {
        eprintln!("REO not deployed, skipping");
        return Ok(());
    }

    eprintln!("=== ReoTestPlan 6.5: View Functions Zero for Ineligible ===");

    let original_period = net.reo_eligibility_period()?;
    let original_validation = net.reo_validation_enabled()?;

    // Enable validation and renew so indexer starts eligible
    net.reo_set_validation(true)?;
    net.reo_renew_indexer(&net.indexer_address)?;
    assert!(
        net.reo_is_eligible(&net.indexer_address)?,
        "Indexer should be eligible after renewal"
    );

    // Get an active allocation
    let allocs = net.query_active_allocations(&net.indexer_address).await?;
    let allocs = allocs.as_array().context("expected allocation array")?;
    let active = allocs.first().context("no active allocation found")?;
    let alloc_id = active["id"].as_str().context("allocation missing id")?;
    eprintln!("  Active allocation: {alloc_id}");

    // Check rewards while eligible — may be non-zero
    let rewards_eligible = net.rewards_pending(alloc_id)?;
    eprintln!("  Pending rewards (eligible): {rewards_eligible}");

    // Make indexer ineligible: set short period and advance time
    net.reo_set_eligibility_period(60)?;
    net.advance_time(65).await?;

    assert!(
        !net.reo_is_eligible(&net.indexer_address)?,
        "Indexer should be ineligible after period expiry"
    );

    // Check rewards while ineligible — should be 0
    let rewards_ineligible = net.rewards_pending(alloc_id)?;
    eprintln!("  Pending rewards (ineligible): {rewards_ineligible}");

    assert_eq!(
        rewards_ineligible, 0,
        "getRewards() should return 0 for ineligible indexer, got {rewards_ineligible}"
    );

    // Restore original state
    net.reo_set_eligibility_period(original_period)?;
    net.reo_set_validation(original_validation)?;
    net.reo_renew_indexer(&net.indexer_address)?;
    eprintln!("  Restored period={original_period}s, validation={original_validation}");

    Ok(())
}
