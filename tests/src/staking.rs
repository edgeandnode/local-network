//! Staking and provision management operations.
//!
//! Higher-level functions that emulate what Explorer UI and `graph indexer` CLI
//! do for stake and provision management. Each function maps to a specific
//! BaselineTestPlan operation.
//!
//! Mapping:
//!   - `stake_tokens` → Explorer "Add Stake" (BaselineTestPlan 2.1)
//!   - `unstake_tokens` → Explorer "Unstake" (BaselineTestPlan 2.2)
//!   - `provision_add` → `graph indexer provisions add` (BaselineTestPlan 3.2)
//!   - `provision_thaw` → `graph indexer provisions thaw` (BaselineTestPlan 3.3)
//!   - `provision_deprovision` → `graph indexer provisions remove` (BaselineTestPlan 3.4)

use anyhow::{Context, Result};

use crate::TestNetwork;
use crate::cast::cast_parse_uint;

impl TestNetwork {
    // --- Stake Management (BaselineTestPlan Cycle 2) ---

    /// Add stake to the indexer via `HorizonStaking.stakeTo()`.
    /// Emulates Explorer "Add Stake" (BaselineTestPlan 2.1).
    ///
    /// Account0 approves and stakes GRT to the indexer. In production,
    /// the indexer does this through Explorer using their own GRT.
    /// `amount_wei` is in wei (e.g., "1000000000000000000000" for 1000 GRT).
    pub fn stake_tokens(&self, amount_wei: &str) -> Result<()> {
        self.cast_send(
            &self.contracts.grt_token,
            "approve(address,uint256)",
            &[&self.contracts.horizon_staking, amount_wei],
        )?;
        self.cast_send(
            &self.contracts.horizon_staking,
            "stakeTo(address,uint256)",
            &[&self.indexer_address, amount_wei],
        )?;
        Ok(())
    }

    /// Unstake idle (unprovisioned) tokens via `HorizonStaking.unstake()`.
    /// Emulates Explorer "Unstake" (BaselineTestPlan 2.2).
    ///
    /// Only works on idle stake (not provisioned or allocated).
    /// Called as the indexer (RECEIVER_SECRET).
    pub fn unstake_tokens(&self, amount_wei: &str) -> Result<()> {
        self.cast_send_as_indexer(
            &self.contracts.horizon_staking,
            "unstake(uint256)",
            &[amount_wei],
        )?;
        Ok(())
    }

    /// Get idle (unprovisioned, unallocated) stake for the indexer.
    pub fn idle_stake(&self) -> Result<u128> {
        let output = self.cast_call(
            &self.contracts.horizon_staking,
            "getIdleStake(address)(uint256)",
            &[&self.indexer_address],
        )?;
        cast_parse_uint(&output)
            .parse()
            .context("parsing idle stake")
    }

    // --- Provision Management (BaselineTestPlan Cycle 3) ---

    /// Add idle stake to the SubgraphService provision.
    /// Emulates `graph indexer provisions add` (BaselineTestPlan 3.2).
    ///
    /// Moves tokens from idle stake into the provision for SubgraphService.
    /// Called as the indexer (RECEIVER_SECRET).
    pub fn provision_add(&self, amount_wei: &str) -> Result<()> {
        self.cast_send_as_indexer(
            &self.contracts.horizon_staking,
            "addToProvision(address,address,uint256)",
            &[
                &self.indexer_address,
                &self.contracts.subgraph_service,
                amount_wei,
            ],
        )?;
        Ok(())
    }

    /// Initiate thawing from the SubgraphService provision.
    /// Emulates `graph indexer provisions thaw` (BaselineTestPlan 3.3).
    ///
    /// Starts the thawing process. Tokens remain locked until the thawing
    /// period expires, then `provision_deprovision()` completes the removal.
    /// Called as the indexer (RECEIVER_SECRET).
    pub fn provision_thaw(&self, amount_wei: &str) -> Result<()> {
        self.cast_send_as_indexer(
            &self.contracts.horizon_staking,
            "thaw(address,address,uint256)",
            &[
                &self.indexer_address,
                &self.contracts.subgraph_service,
                amount_wei,
            ],
        )?;
        Ok(())
    }

    /// Complete removal of thawed stake from provision.
    /// Emulates `graph indexer provisions remove` (BaselineTestPlan 3.4).
    ///
    /// Can only succeed after the thawing period has elapsed.
    /// `n_thaw_requests` is typically 1 (one thaw request to process).
    /// Called as the indexer (RECEIVER_SECRET).
    pub fn provision_deprovision(&self, n_thaw_requests: u64) -> Result<()> {
        self.cast_send_as_indexer(
            &self.contracts.horizon_staking,
            "deprovision(address,address,uint256)",
            &[
                &self.indexer_address,
                &self.contracts.subgraph_service,
                &n_thaw_requests.to_string(),
            ],
        )?;
        Ok(())
    }

    /// Get the thawing period (seconds) for the indexer's SubgraphService provision.
    /// Queries the network subgraph for the provision's thawingPeriod field.
    pub async fn provision_thawing_period(&self) -> Result<u64> {
        let provisions = self.query_provisions(&self.indexer_address).await?;
        let provisions = provisions
            .as_array()
            .context("provisions should be an array")?;
        let first = provisions
            .first()
            .context("no provision found for indexer")?;
        first["thawingPeriod"]
            .as_u64()
            .or_else(|| first["thawingPeriod"].as_str().and_then(|s| s.parse().ok()))
            .context("thawingPeriod not found in provision")
    }
}
